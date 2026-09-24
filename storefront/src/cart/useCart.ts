'use client';

/**
 * The cart hook - the ONLY bridge between React and cart persistence.
 *
 * STORAGE BOUNDARY: this module calls loadCart/saveCart and nothing else. It
 * never names `localStorage`, never builds a key and never serialises; all of
 * that lives in cartStorage.ts, which is the single module allowed to touch the
 * store. tests/sf-source-rules.test.mjs enforces that allowlist.
 *
 * STATIC-EXPORT RULE: every storefront route is a static document, so the
 * served bytes are identical for every visitor and a stored cart can only be
 * applied AFTER hydration. State therefore starts EMPTY - which is exactly what
 * the prerendered HTML shows - and the stored cart is read in a LAYOUT effect,
 * so it lands in the same commit, before the browser paints the hydrated frame.
 * `ready` reports whether that read has happened, so a consumer can distinguish
 * an empty cart the visitor really has from one we have not yet read.
 * (Phrased without a quoted clause on purpose: tests/contract.test.mjs scans
 * RAW source for `from "..."`, so prose in that shape reads as a bare import.)
 *
 * ONE WRITER PER TAB. Two tabs on the same slug each own their own React state;
 * the last write wins. No `storage` event listener is installed, because
 * cross-tab cart merging is not designed anywhere in the approved handoff and
 * inventing a merge rule would be inventing product behaviour.
 */
import { useCallback, useLayoutEffect, useMemo, useRef, useState } from 'react';
import { addLine, removeLine, summarise, updateLine, type CartSummary } from './cartModel';
import { emptyCart, loadCart, saveCart } from './cartStorage';
import type { CartState, MenuItem, ModifierGroup, ModifierSelections } from '@/source/types';

export interface CartDraft {
  readonly itemId: string;
  readonly qty: number;
  readonly selections: ModifierSelections;
  readonly note: string;
}

export interface CartApi {
  /** The resolved view: only lines whose item still exists in the menu. */
  readonly summary: CartSummary;
  /** False until the stored cart has been read, i.e. until after hydration. */
  readonly ready: boolean;
  readonly add: (draft: CartDraft) => void;
  readonly update: (lineId: string, draft: Omit<CartDraft, 'itemId'>) => void;
  readonly remove: (lineId: string) => void;
  /**
   * Empties the cart on this device. The ONE designed caller is the status
   * screen's "order again" (INTERACTIONS.md:115 "clears the cart and returns
   * to the menu"); nothing clears a cart on a send, a failure or a duplicate.
   */
  readonly clear: () => void;
  readonly state: CartState;
}

export function useCart(
  slug: string,
  menuVersion: string,
  items: readonly MenuItem[],
  groups: readonly ModifierGroup[],
): CartApi {
  const [state, setState] = useState<CartState>(() => emptyCart(slug, menuVersion));
  const [ready, setReady] = useState(false);

  // Guards the first save: without it the mount-time effect would immediately
  // write the empty starting state over a cart the visitor already had.
  const loaded = useRef(false);

  // The menu, read inside the load effect without making it a dependency: the
  // fixture is a module constant, and re-running the load on every render would
  // undo the visitor's own changes.
  const itemsRef = useRef(items);
  itemsRef.current = items;
  const groupsRef = useRef(groups);
  groupsRef.current = groups;

  // The handlers below are called from event handlers, so they must see the
  // CURRENT state without being rebuilt whenever it changes. A ref synchronised
  // during render is the cheapest correct way.
  const stateRef = useRef(state);
  stateRef.current = state;

  useLayoutEffect(() => {
    loaded.current = false;
    setReady(false);
    const stored = loadCart(slug, menuVersion);
    // PRUNE ON LOAD. A line naming an item the menu no longer has is skipped at
    // render time, so it would otherwise sit in storage forever: invisible,
    // uncountable and - with no cart screen in this phase - impossible for the
    // visitor to remove. Rewriting the pruned cart keeps what is stored equal
    // to what is shown.
    const usable = summarise(stored, itemsRef.current, groupsRef.current);
    const pruned =
      usable.lines.length === stored.lines.length
        ? stored
        : { ...stored, lines: usable.lines.map((l) => l.line) };
    setState(pruned);
    loaded.current = true;
    if (pruned !== stored) saveCart(pruned);
    setReady(true);
  }, [slug, menuVersion]);

  const commit = useCallback((next: CartState) => {
    setState((current) => {
      // An unknown line id makes the model return the identical object. Nothing
      // changed, so nothing is written.
      if (next === current) return current;
      if (loaded.current) saveCart(next);
      return next;
    });
  }, []);

  const add = useCallback((draft: CartDraft) => commit(addLine(stateRef.current, draft)), [
    commit,
  ]);

  const update = useCallback(
    (lineId: string, draft: Omit<CartDraft, 'itemId'>) =>
      commit(updateLine(stateRef.current, lineId, draft)),
    [commit],
  );

  const remove = useCallback(
    (lineId: string) => commit(removeLine(stateRef.current, lineId)),
    [commit],
  );

  const clear = useCallback(() => {
    if (stateRef.current.lines.length === 0) return;
    commit(emptyCart(slug, menuVersion));
  }, [commit, menuVersion, slug]);

  const summary = useMemo(() => summarise(state, items, groups), [state, items, groups]);

  return { summary, ready, add, update, remove, clear, state };
}
