'use client';

import dynamic from 'next/dynamic';
import type { ReactNode } from 'react';
import { CheckoutDraftProvider } from './CheckoutDraftProvider';

const LiveProvider = dynamic(() => import('./LiveCheckoutProvider').then((module) => module.LiveCheckoutProvider), { ssr: true });

/** The layout keeps tenant state mounted; only its live variant loads recovery. */
export function CheckoutEntry({ source, slug, children }: { source: 'fixture' | 'live'; slug: string; children: ReactNode }) {
  return source === 'live'
    ? <LiveProvider slug={slug}>{children}</LiveProvider>
    : <CheckoutDraftProvider slug={slug}>{children}</CheckoutDraftProvider>;
}
