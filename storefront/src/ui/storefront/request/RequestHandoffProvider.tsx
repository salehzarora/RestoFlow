'use client';

/**
 * THE D/E HANDOFF - APPLICATION MEMORY ONLY.
 *
 * When a send is accepted, the review step records WHAT was sent - the
 * noncontact summary - so the received screen can show it without asking a
 * backend that does not exist. It lives in React state in a provider mounted
 * in each root layout: the only place that stays mounted across the soft
 * navigation from `/s/:slug/review` to `/r/:ref`, which sit under different
 * segment layouts. A full document load empties it, by design, and the same
 * URL then renders the status view from the source.
 *
 * WHAT IT MAY CARRY (FINISH 4.2): the ref, the display code, service, zone,
 * line ids with quantities and selections, the quoted amounts, the instant.
 * WHAT IT MAY NEVER CARRY: a name, a phone, an address field, a delivery note,
 * a kitchen note. The type has no slot for them and a source rule greps this
 * file for their names.
 *
 * NO persistence of any kind, no module-level variable: a provider instance
 * per document, keyed by tenant and ref, so one visitor's request is never
 * observable from another render or another tab.
 */
import { createContext, useCallback, useContext, useMemo, useState, type ReactNode } from 'react';
import type { Minor, ModifierSelections } from '@/source/types';

export interface HandoffLine {
  readonly itemId: string;
  readonly qty: number;
  readonly selections: ModifierSelections;
  readonly lineTotalMinor: Minor;
}

export interface RequestHandoff {
  readonly slug: string;
  readonly ref: string;
  /** 'accepted' opens the received view once; 'duplicate' opens status. */
  readonly kind: 'accepted' | 'duplicate';
  readonly service: 'pickup' | 'delivery';
  readonly zoneId: string;
  readonly zoneName: string | null;
  readonly lines: readonly HandoffLine[];
  readonly subtotalMinor: Minor;
  readonly feeMinor: Minor;
  readonly taxMinor: Minor;
  readonly totalMinor: Minor;
  /** Epoch ms at the send, from the clock at that moment. */
  readonly createdAt: number;
  /** True once the received view has been shown; the same URL then renders status. */
  readonly seen: boolean;
}

interface HandoffApi {
  readonly handoff: RequestHandoff | null;
  readonly set: (handoff: RequestHandoff) => void;
  /** Marks the received view as shown for this ref. */
  readonly markSeen: (ref: string) => void;
  readonly clear: () => void;
}

const HandoffContext = createContext<HandoffApi | null>(null);

export function RequestHandoffProvider({ children }: { children: ReactNode }) {
  const [handoff, setHandoff] = useState<RequestHandoff | null>(null);
  const set = useCallback((next: RequestHandoff) => setHandoff(next), []);
  const markSeen = useCallback(
    (ref: string) =>
      setHandoff((h) => (h === null || h.ref !== ref || h.seen ? h : { ...h, seen: true })),
    [],
  );
  const clear = useCallback(() => setHandoff(null), []);
  const api = useMemo(() => ({ handoff, set, markSeen, clear }), [handoff, set, markSeen, clear]);
  return <HandoffContext.Provider value={api}>{children}</HandoffContext.Provider>;
}

/** Null outside the provider, so a stray consumer cannot invent a handoff. */
export function useRequestHandoff(): HandoffApi | null {
  return useContext(HandoffContext);
}
