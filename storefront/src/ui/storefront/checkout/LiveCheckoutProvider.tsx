'use client';

import type { ReactNode } from 'react';
import { CartMemoryProvider } from '@/cart/CartMemoryProvider';
import { CheckoutDraftProvider } from './CheckoutDraftProvider';
import { LiveOrderProvider } from './LiveOrderProvider';

/** Persistent tenant layout for live cart, private recovery and customer draft. */
export function LiveCheckoutProvider({ slug, children }: { slug: string; children: ReactNode }) {
  return (
    <CartMemoryProvider slug={slug}>
      <LiveOrderProvider slug={slug}>
        <CheckoutDraftProvider slug={slug}>{children}</CheckoutDraftProvider>
      </LiveOrderProvider>
    </CartMemoryProvider>
  );
}
