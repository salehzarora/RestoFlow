'use client';

/**
 * THE CHECKOUT DRAFT - APPLICATION MEMORY ONLY.
 *
 * This is the single owner of the visitor's contact and delivery fields. It
 * deliberately has NO persistence of any kind: no localStorage, no
 * sessionStorage, no cookie, no IndexedDB, no URL or history state, no
 * window.name. A reload starts empty, by design, and that is the privacy
 * contract Phase D is required to keep.
 *
 * It is keyed by the CANONICAL tenant slug. Changing tenant resets the draft
 * rather than letting one tenant observe another's.
 */
import { createContext, useCallback, useContext, useMemo, useRef, useState, type ReactNode } from 'react';
import { EMPTY_DRAFT, type CheckoutDraft } from './draft';

// The SHAPE lives in draft.ts so validation, the submit contract and the tests
// can read it without importing React. This file owns the INSTANCE and the
// memory-only rule above.
export { EMPTY_DRAFT };
export type { CheckoutDraft, Service } from './draft';

interface DraftApi {
  readonly draft: CheckoutDraft;
  readonly set: (patch: Partial<CheckoutDraft>) => void;
  readonly reset: () => void;
}

const DraftContext = createContext<DraftApi | null>(null);

export function CheckoutDraftProvider({ slug, children }: { slug: string; children: ReactNode }) {
  const [draft, setDraft] = useState<CheckoutDraft>(EMPTY_DRAFT);

  // Tenant isolation: if the canonical slug ever changes under this provider,
  // the draft is dropped rather than carried across tenants.
  const owner = useRef(slug);
  if (owner.current !== slug) {
    owner.current = slug;
    if (draft !== EMPTY_DRAFT) setDraft(EMPTY_DRAFT);
  }

  const set = useCallback((patch: Partial<CheckoutDraft>) => {
    setDraft((d) => ({ ...d, ...patch }));
  }, []);
  const reset = useCallback(() => setDraft(EMPTY_DRAFT), []);
  const api = useMemo(() => ({ draft, set, reset }), [draft, set, reset]);

  return <DraftContext.Provider value={api}>{children}</DraftContext.Provider>;
}

/** Null outside the provider, so a stray consumer cannot invent a draft. */
export function useCheckoutDraft(): DraftApi | null {
  return useContext(DraftContext);
}
