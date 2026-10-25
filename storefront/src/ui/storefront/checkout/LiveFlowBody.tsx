'use client';

import { useEffect, useMemo, useRef } from 'react';
import { usePathname, useRouter } from 'next/navigation';
import { buildQuote } from '@/money/quote';
import { storefrontMessages } from '@/i18n/storefront';
import type { OrderMessages } from '@/i18n/orders';
import { cartPath, checkoutPath, menuPath, reviewPath } from '@/routes/routes';
import { cartNavigationHref } from '@/routes/cart-navigation';
import { useCartApi } from '../cart/CartContext';
import { useCheckoutDraft, EMPTY_DRAFT } from './CheckoutDraftProvider';
import { CartScreen } from './CartScreen';
import { DetailsScreen } from './DetailsScreen';
import type { FlowProps } from './FlowRuntime';
import { CartHeader } from './flowParts';
import { orderingBlocker, orderingReason } from './eligibility';
import { validateCheckout } from './validation';
import { useLiveOrder } from './LiveOrderProvider';
import { LiveReviewScreen } from './LiveReviewScreen';
import { LiveRequestRuntime } from '../request/LiveRequestRuntime';
import s from './flow.module.css';

/** Live checkout never reads demo tokens or constructs the fixture gateway. */
export function LiveFlowBody(props: FlowProps & { orderCopy: OrderMessages }) {
  const { locale, slug, screen, tenant, state, motion, items, groups, taxRateBp, orderEndpointOrigin } = props;
  const m = storefrontMessages(locale);
  const copy = props.orderCopy;
  const router = useRouter();
  const pathname = usePathname();
  const cart = useCartApi();
  const draftApi = useCheckoutDraft();
  const draft = draftApi?.draft ?? EMPTY_DRAFT;
  const { controller, snapshot } = useLiveOrder(orderEndpointOrigin);
  const leaving = useRef(false);
  const quote = useMemo(() => cart ? buildQuote({ cart: cart.state, items, groups, service: 'pickup', zone: null, taxRateBp }) : null, [cart, items, groups, taxRateBp]);
  const ready = cart !== null && cart.ready && quote !== null;
  const details = quote ? validateCheckout(draft, quote, { pickup: tenant.pickupEnabled, delivery: false }, true) : null;
  const withinLimits = cart !== null && cart.state.lines.length <= 20 && cart.summary.itemCount <= 50;
  const reason = orderingReason(orderingBlocker(state, tenant.orderingEnabled), m, tenant.opensAt);
  const blocked = reason ?? (!tenant.pickupEnabled ? copy.orderingUnavailable : controller === null ? copy.unsupported : null);
  const hrefs = {
    menu: cartNavigationHref(menuPath(locale, slug), pathname),
    cart: cartNavigationHref(cartPath(locale, slug), pathname),
    checkout: cartNavigationHref(checkoutPath(locale, slug), pathname),
    review: cartNavigationHref(reviewPath(locale, slug), pathname),
  };

  useEffect(() => {
    if (leaving.current) return;
    // Recovery begins in the preceding effect. Read its current snapshot so a
    // reload cannot redirect an empty cart before the status response arrives.
    const current = controller?.getSnapshot() ?? snapshot;
    if (current.result !== null || current.recovered || ['unknown', 'not_found', 'unavailable'].includes(current.phase)) {
      if (current.result !== null) draftApi?.reset();
      if (screen !== 'review') router.replace(reviewPath(locale, slug));
      return;
    }
    if (!ready || screen === 'cart') return;
    if (!tenant.orderingEnabled || !withinLimits || quote.lines.length === 0) router.replace(hrefs.cart);
    else if (screen === 'payment') router.replace(details?.ok ? hrefs.review : hrefs.checkout);
    else if (screen === 'review' && !details?.ok) router.replace(hrefs.checkout);
  }, [controller, snapshot, draftApi?.reset, ready, screen, tenant.orderingEnabled, withinLimits, quote, details?.ok, router, locale, slug, hrefs.cart, hrefs.checkout, hrefs.review]);

  if (screen === 'review' && (snapshot.result !== null || snapshot.recovered || ['unknown', 'not_found', 'unavailable'].includes(snapshot.phase))) {
    return <LiveRequestRuntime locale={locale} copy={copy} slug={slug} origin={orderEndpointOrigin} tenant={{ name: tenant.name, logo: tenant.logo ?? null }} publicPhone={tenant.publicPhone} onOrderAgain={() => {
      if (controller?.startNewOrder().phase !== 'idle') return;
      leaving.current = true;
      cart?.clear();
      draftApi?.reset();
      router.push(menuPath(locale, slug));
    }} />;
  }

  if (!ready) return <div className={s.screen} data-sf-screen={screen} data-sf-pending=""><CartHeader m={m} backHref={hrefs.menu} count={0} /><div className={s.body} /></div>;
  if (screen === 'cart') return <CartScreen m={m} cart={cart} quote={quote} menuHref={hrefs.menu} state={state} orderingEnabled={tenant.orderingEnabled} opensAt={tenant.opensAt} motion={motion} notice={null} pending={false} onDismissNotice={() => undefined} onCheckout={() => { if (!blocked && withinLimits) router.push(hrefs.checkout); }} checkoutBlock={withinLimits ? blocked : copy.limits} estimateCopy={copy.estimate} />;
  if (screen === 'checkout' || screen === 'payment') return <DetailsScreen m={m} draft={draft} set={draftApi?.set ?? (() => undefined)} quote={quote} tenant={tenant} zones={[]} motion={motion} backHref={hrefs.cart} pending={false} blockedReason={blocked} onContinue={() => { if (!blocked && withinLimits && details?.ok) router.push(hrefs.review); }} onAddItems={() => router.push(hrefs.menu)} pickupCopy={copy} />;
  return <LiveReviewScreen m={m} copy={copy} cart={cart} draft={draft} quote={quote} tenant={tenant} motion={motion} backHref={hrefs.checkout} blockedReason={blocked} submittable={withinLimits && details?.ok === true && tenant.orderingEnabled && state === 'open'} controller={controller} snapshot={snapshot} onEditDetails={() => router.push(hrefs.checkout)} />;
}
