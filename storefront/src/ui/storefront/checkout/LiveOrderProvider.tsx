'use client';

import { createContext, useContext, useEffect, useMemo, useRef, useSyncExternalStore, type ReactNode } from 'react';
import { createOrderController, type OrderController, type OrderSnapshot } from '@/orders';

const EMPTY: OrderSnapshot = Object.freeze({ phase: 'idle', result: null, error: null, canRetry: false, recovered: false });
const LiveOrders = createContext<((origin: string) => OrderController) | null>(null);

/** One in-memory submission owner across this tenant's checkout/status routes. */
export function LiveOrderProvider({ slug, children }: { slug: string; children: ReactNode }) {
  const held = useRef<{ slug: string; origin: string; controller: OrderController } | null>(null);
  if (held.current?.slug !== slug) held.current = null;
  const get = useMemo(() => (origin: string) => {
    if (held.current?.slug !== slug || held.current.origin !== origin) {
      held.current = { slug, origin, controller: createOrderController({ slug, origin }) };
    }
    return held.current.controller;
  }, [slug]);
  return <LiveOrders.Provider value={get}>{children}</LiveOrders.Provider>;
}

export function useLiveOrder(origin?: string) {
  const get = useContext(LiveOrders);
  const controller = useMemo(() => origin && get ? get(origin) : null, [origin, get]);
  const snapshot = useSyncExternalStore(controller?.subscribe ?? (() => () => undefined), controller?.getSnapshot ?? (() => EMPTY), () => EMPTY);
  useEffect(() => { if (controller) void controller.recover(); }, [controller]);
  return { controller, snapshot };
}
