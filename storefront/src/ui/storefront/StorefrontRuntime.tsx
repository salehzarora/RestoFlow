'use client';

/**
 * THE ONE INTERACTIVE ISLAND for cart + product sheet.
 *
 * WHY NOT `useSearchParams`. Reading it would put this subtree behind a
 * `<Suspense>` boundary and bail the route out to client-side rendering, which
 * would empty the static menu document that tests/output/output.test.mjs
 * asserts on. `?item=` is therefore read from `location.search` in an effect
 * and kept in step with a `popstate` listener - the fallback the execution
 * packet itself records (PACKET:1042), and the same shape IntroGate.tsx
 * already uses. `location` is NEVER read during render: the first client render
 * is identical to the server HTML, and the URL is applied afterwards.
 *
 * WHY EVENT DELEGATION. Menu cards stay SERVER-rendered. Giving each card an
 * onClick would ship every card's markup as JavaScript and spend first-load
 * budget that is already 93% committed. Instead the cards carry `data-sf-item`
 * (the prototype's own `role="button" tabindex` pattern) and this island
 * listens once, on its own subtree's document.
 *
 * WHAT IS DELIBERATELY ABSENT: no cart route, no checkout, no line management,
 * no request persistence. Those are Phase D and the dock CTA stays disabled
 * until they exist.
 */
import { useCallback, useEffect, useLayoutEffect, useRef, useState, type ReactNode } from 'react';
import { useCart, type CartDraft } from '@/cart/useCart';
import { findLine } from '@/cart/cartModel';
import { storefrontMessages } from '@/i18n/storefront';
import type { Locale } from '@/i18n/locales';
import { groupsFor } from '@/source/modifier-fixture';
import type { MenuItem, MotionMode, ServiceState } from '@/source/types';
import { CartScope } from './cart/CartRuntime';
import { ProductSheet, type SheetDraft } from './product/ProductSheet';
import product from './product/product.module.css';

/** How long a toast stays up, matching the prototype (Storefront.dc.html:703). */
const TOAST_MS = 2200;

/** Marks the history entry this component pushed for an open sheet. */
const SHEET_MARK = 'sfSheet';

interface SheetTarget {
  readonly itemId: string;
  readonly lineId: string | null;
}

/**
 * The sheet the CURRENT URL asks for, or null. Ids are validated against the
 * real menu by the caller: an `?item=` naming nothing is simply not a sheet.
 */
function targetFromSearch(search: string): SheetTarget | null {
  const params = new URLSearchParams(search);
  const itemId = params.get('item');
  if (itemId === null || itemId === '') return null;
  const lineId = params.get('line');
  return { itemId, lineId: lineId === null || lineId === '' ? null : lineId };
}

function searchWithItem(search: string, target: SheetTarget | null): string {
  const params = new URLSearchParams(search);
  params.delete('item');
  params.delete('line');
  if (target !== null) {
    params.set('item', target.itemId);
    if (target.lineId !== null) params.set('line', target.lineId);
  }
  const text = params.toString();
  return text === '' ? '' : `?${text}`;
}

export function StorefrontRuntime({
  slug,
  menuVersion,
  items,
  locale,
  motion,
  state,
  opensAt,
  children,
}: {
  slug: string;
  menuVersion: string;
  items: readonly MenuItem[];
  /**
   * The LOCALE, not the dictionary. A dictionary handed across the server ->
   * client boundary is serialised into every document's RSC payload - four
   * files per document, eight home/search documents - while the client bundle
   * already carries all three dictionaries for the flow. Resolving it here
   * costs no bytes; passing it cost ~290 KB of the export (E-OPT-1).
   */
  locale: Locale;
  motion: MotionMode;
  state: ServiceState;
  opensAt: string;
  /**
   * The screen's own tree. It is rendered INSIDE the cart scope so DockSlot and
   * AsideSlot can each sit in their correct layout parent (see CartRuntime).
   */
  children?: ReactNode;
}) {
  const m = storefrontMessages(locale);
  const cart = useCart(slug, menuVersion, items);
  const [target, setTarget] = useState<SheetTarget | null>(null);
  const [toast, setToast] = useState<{ text: string; nonce: number } | null>(null);

  /**
   * Marks the history entry this component pushed. It is stored in the history
   * STATE, not in a ref: a ref cannot survive a reload, and without the marker
   * popstate cannot tell an entry this component pushed apart from any other
   * one - so after a reload or a Forward, closing would either push a duplicate
   * entry or call back() on an entry that is not ours and leave the site.
   * (Phrased without a quoted clause: tests/contract.test.mjs scans RAW source
   * for `from "..."`, so prose in that shape reads as a bare import.)
   */
  const pushed = useRef(false);

  // --- URL <-> sheet --------------------------------------------------------
  useLayoutEffect(() => {
    setTarget(targetFromSearch(window.location.search));
    pushed.current = window.history.state?.[SHEET_MARK] === true;
    const onPop = () => {
      pushed.current = window.history.state?.[SHEET_MARK] === true;
      setTarget(targetFromSearch(window.location.search));
    };
    window.addEventListener('popstate', onPop);
    return () => window.removeEventListener('popstate', onPop);
  }, []);

  const open = useCallback((next: SheetTarget) => {
    // The hash is carried through: a category anchor in the address bar must
    // survive opening a sheet, or a URL copied at that moment loses it.
    const url = `${window.location.pathname}${searchWithItem(window.location.search, next)}${window.location.hash}`;
    window.history.pushState({ [SHEET_MARK]: true }, '', url);
    pushed.current = true;
    setTarget(next);
  }, []);

  const close = useCallback(() => {
    // Unmount the sheet SYNCHRONOUSLY in both paths. history.back() only fires
    // popstate on a later task, and until it did the sheet stayed mounted and
    // live - so a second tap on the CTA could add the same line twice.
    setTarget(null);
    if (pushed.current) {
      // Back is the only closer, so the close button, Esc and the scrim all
      // agree with the browser's own Back and the stack never accumulates.
      pushed.current = false;
      window.history.back();
      return;
    }
    const url = `${window.location.pathname}${searchWithItem(window.location.search, null)}${window.location.hash}`;
    window.history.replaceState(null, '', url);
  }, []);

  // --- opening from a server-rendered card ---------------------------------
  useEffect(() => {
    function hostOf(node: EventTarget | null): HTMLElement | null {
      if (!(node instanceof Element)) return null;
      const host = node.closest<HTMLElement>('[data-sf-item]');
      if (host === null) return null;
      // Sold out is not openable (COMPONENT_INVENTORY.md:112).
      return host.getAttribute('aria-disabled') === 'true' ? null : host;
    }
    // A cart line's Edit control carries BOTH attributes, so the same
    // delegation opens the sheet pre-filled and the sheet replaces that line
    // instead of appending a second one. The item/line ownership check below
    // still decides whether the pairing is legitimate.
    function targetOf(host: HTMLElement | null): SheetTarget | null {
      const id = host?.dataset.sfItem;
      if (id === undefined || host === null) return null;
      const line = host.dataset.sfLine;
      return { itemId: id, lineId: line === undefined || line === '' ? null : line };
    }
    function onClick(event: MouseEvent) {
      const next = targetOf(hostOf(event.target));
      if (next === null) return;
      event.preventDefault();
      open(next);
    }
    function onKeyDown(event: KeyboardEvent) {
      if (event.key !== 'Enter' && event.key !== ' ') return;
      const next = targetOf(hostOf(event.target));
      if (next === null) return;
      // role="button" must answer Enter and Space like a real button does.
      event.preventDefault();
      open(next);
    }
    document.addEventListener('click', onClick);
    document.addEventListener('keydown', onKeyDown);
    return () => {
      document.removeEventListener('click', onClick);
      document.removeEventListener('keydown', onKeyDown);
    };
  }, [open]);

  // Carry an open sheet across a language switch. The locale anchors are
  // prerendered with a bare path, so without this a visitor who changes
  // language with the sheet open lands on the menu with the sheet gone -
  // contradicting INTERACTIONS.md:44, which guarantees the CURRENT screen is
  // preserved. `a[hreflang]` is LanguageMenu's own stable markup.
  useEffect(() => {
    const anchors = document.querySelectorAll<HTMLAnchorElement>('a[hreflang]');
    anchors.forEach((anchor) => {
      const url = new URL(anchor.href, window.location.href);
      anchor.setAttribute('href', `${url.pathname}${searchWithItem(url.search, target)}`);
    });
  }, [target]);

  // --- toast ----------------------------------------------------------------
  // The nonce matters: refusing the same option twice produces the SAME text,
  // and without it React bails out of the state update, the effect never
  // re-runs, and the second refusal shows no toast at all (or is cut short by
  // the first one's timer).
  const showToast = useCallback(
    (text: string) => setToast((current) => ({ text, nonce: (current?.nonce ?? 0) + 1 })),
    [],
  );
  useEffect(() => {
    if (toast === null) return undefined;
    const timer = window.setTimeout(() => setToast(null), TOAST_MS);
    return () => window.clearTimeout(timer);
  }, [toast]);

  // --- resolve the URL against the real menu --------------------------------
  const item = target === null ? null : (items.find((i) => i.id === target.itemId) ?? null);
  // An `?item=` that names nothing, or a sold-out item, opens no sheet and is
  // left in the URL untouched rather than redirected: a static export has no
  // server to redirect from, and silently rewriting a visitor's URL is worse
  // than ignoring a parameter we do not recognise.
  const openable = item !== null && !item.soldOut;
  // The line must belong to THIS item. `?item=9&line=<a line holding item 1>`
  // would otherwise open a sheet for item 9 whose submit REWRITES item 1's
  // line - silently replacing a cart line with a different product.
  const namedLine = target?.lineId == null ? null : findLine(cart.state, target.lineId);
  const editingLine =
    namedLine !== null && item !== null && namedLine.itemId === item.id ? namedLine : null;

  const initial: SheetDraft | undefined =
    editingLine === null
      ? undefined
      : { qty: editingLine.qty, selections: editingLine.selections, note: editingLine.note };

  const submit = useCallback(
    (draft: SheetDraft) => {
      if (item === null) return;
      const name = item.name;
      if (editingLine !== null) {
        cart.update(editingLine.lineId, draft);
        showToast(`${m.updateItem} · ${name}`);
      } else {
        const full: CartDraft = { itemId: item.id, ...draft };
        cart.add(full);
        showToast(`${m.addToCart} · ${name}`);
      }
      close();
    },
    [cart, close, editingLine, item, m.addToCart, m.updateItem, showToast],
  );



  const motionClass =
    motion === 'calm' ? '' : motion === 'lively' ? product.motionLively : product.motionFull;

  return (
    <CartScope cart={cart}>
      {children}

      {openable && item !== null ? (
        <ProductSheet
          key={`${item.id}:${target?.lineId ?? ''}`}
          item={item}
          groups={groupsFor(item.groupIds)}
          m={m}
          motion={motion}
          initial={initial}
          editing={editingLine !== null}
          onClose={close}
          onSubmit={submit}
          onToast={showToast}
        />
      ) : null}

      {toast === null ? null : (
        // The motion class must sit on an ANCESTOR: the animation rules are
        // descendant selectors, so putting both classes on one element would
        // match nothing and silently drop the animation.
        <div className={`${product.host} ${motionClass}`}>
          <div className={product.toast} role="status" data-sf-toast="product">
            <span className={product.toastPill}>{toast.text}</span>
          </div>
        </div>
      )}
    </CartScope>
  );
}
