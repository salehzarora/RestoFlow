'use client';

/**
 * THE PHASE D RUNTIME - one client island shared by all four flow routes.
 *
 * WHY THE FIXTURE IS IMPORTED HERE RATHER THAN PASSED IN.
 * Every storefront route is a static document. A menu handed from a server
 * component to a client one is serialised into EVERY document's RSC payload;
 * measured, that cost 424,033 bytes across the sixteen Phase D documents. The
 * same module imported by the CLIENT lands in one shared chunk instead, for
 * 11,702 bytes total - a 412,331-byte saving against a hard 4 MiB ceiling this
 * phase may not raise. The same reasoning applies to the dictionaries.
 *
 * WHY ALL FOUR SCREENS SHARE ONE RUNTIME. They share one cart, one quote and
 * one draft. Splitting them would mean four copies of that wiring and four
 * chances for them to disagree about the total.
 *
 * WHAT IS DELIBERATELY ABSENT: no storage of any customer field, no network
 * call, no analytics, no WhatsApp.
 *
 * THE HANDOFF (Phase E). An accepted send records the NONCONTACT summary of
 * what was sent in the in-memory handoff and navigates to `/r/:ref`; the
 * duplicate banner's "view status" carries the same summary, marked seen and
 * without a send instant, so the same route opens the status view directly.
 * The cart is NOT cleared by a send, a failure or a duplicate (the prototype
 * keeps it, :728); only the status screen's "order again" clears it.
 */
import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState } from 'react';
import { useRouter } from 'next/navigation';
import { useCartApi } from '../cart/CartRuntime';
import { StorefrontRuntime } from '../StorefrontRuntime';
import { storefrontMessages } from '@/i18n/storefront';
import type { Locale } from '@/i18n/locales';
import { buildQuote, type Quote, type QuoteInput } from '@/money/quote';
import { raceQuoteSource, useQuote, type QuoteSource } from '@/money/useQuote';
import { MENU_ITEMS, MENU_VERSION, TAX_RATE } from '@/source/menu-fixture';
import { findZone } from '@/source/zones';
import { withRequestScenario } from '@/source/request-scenarios';
import {
  isQuoteRace,
  noticeFor,
  readFlowScenario,
  sendOutcomeFor,
  withFlowScenario,
} from '@/source/flow-scenarios';
import type { MotionMode, ServiceState } from '@/source/types';
import { cartPath, checkoutPath, menuPath, paymentPath, requestPath, reviewPath } from '@/routes/routes';
import { useRequestHandoff, type RequestHandoff } from '../request/RequestHandoffProvider';
import { EMPTY_DRAFT, useCheckoutDraft } from './CheckoutDraftProvider';
import { CartScreen, type CartNotice } from './CartScreen';
import { DetailsScreen, type FlowTenant } from './DetailsScreen';
import { PaymentScreen } from './PaymentScreen';
import { ReviewScreen } from './ReviewScreen';
import { validateCheckout } from './validation';
import { fixtureGateway, type CompletionObserver, type RequestGateway } from './submit';
import { CartHeader, StepHeader } from './flowParts';
import s from './flow.module.css';

export type FlowScreenName = 'cart' | 'checkout' | 'payment' | 'review';

export interface FlowProps {
  readonly locale: Locale;
  readonly slug: string;
  readonly screen: FlowScreenName;
  readonly tenant: FlowTenant;
  readonly state: ServiceState;
  readonly motion: MotionMode;
  /** Test seam. Production passes nothing and gets the fixture source. */
  readonly quoteSource?: QuoteSource;
  readonly gateway?: RequestGateway;
  readonly onComplete?: CompletionObserver;
}

export function FlowRuntime(props: FlowProps) {
  const m = storefrontMessages(props.locale);
  return (
    <StorefrontRuntime
      slug={props.slug}
      menuVersion={MENU_VERSION}
      items={MENU_ITEMS}
      locale={props.locale}
      motion={props.motion}
      state={props.state}
      opensAt={props.tenant.opensAt}
    >
      <FlowBody {...props} />
    </StorefrontRuntime>
  );
}

function FlowBody({
  locale,
  slug,
  screen,
  tenant,
  state,
  motion,
  quoteSource,
  gateway,
  onComplete,
}: FlowProps) {
  const m = storefrontMessages(locale);
  const router = useRouter();
  const cart = useCartApi();
  const draftApi = useCheckoutDraft();
  const draft = draftApi?.draft ?? EMPTY_DRAFT;

  const [fx, setFx] = useState('');
  const [dismissed, setDismissed] = useState(false);
  const handoffApi = useRequestHandoff();

  // The URL is read AFTER hydration, never during render: the first client
  // render has to match the static document byte for byte.
  useLayoutEffect(() => {
    setFx(readFlowScenario(window.location.search));
    const onPop = () => setFx(readFlowScenario(window.location.search));
    window.addEventListener('popstate', onPop);
    return () => window.removeEventListener('popstate', onPop);
  }, []);

  const zone = findZone(draft.zoneId);
  const input: QuoteInput = useMemo(
    () => ({
      cart: cart?.state ?? { schema: 1, slug, menuVersion: MENU_VERSION, lines: [] },
      items: MENU_ITEMS,
      service: draft.service,
      zone,
      taxRate: TAX_RATE,
    }),
    [cart?.state, draft.service, slug, zone],
  );
  const source = quoteSource ?? (isQuoteRace(fx) ? raceQuoteSource : undefined);
  const { quote, pending } = useQuote(input, source);

  const hrefs = useMemo(
    () => ({
      menu: menuPath(locale, slug),
      cart: cartPath(locale, slug),
      checkout: checkoutPath(locale, slug),
      payment: paymentPath(locale, slug),
      review: reviewPath(locale, slug),
    }),
    [locale, slug],
  );

  const ready = cart !== null && cart.ready && quote !== null;

  /*
   * ENTRY GUARDS.
   *
   * A static export makes every URL directly loadable, so a visitor can land
   * on `/payment` having entered nothing at all. Showing a payment step for a
   * request that can never be sent would be a lie, so each step redirects to
   * the first one it is missing a prerequisite for.
   *
   * They run only once the visitor's OWN cart has been read: before that every
   * cart looks empty and the guard would bounce everyone off checkout.
   *
   * `replace`, not `push`, so Back does not land on the page that just
   * redirected and bounce again.
   */
  const redirected = useRef(false);
  useEffect(() => {
    if (!ready || redirected.current) return;
    const empty = quote.lines.length === 0;
    const details = validateCheckout(draft, quote, {
      pickup: tenant.pickupEnabled,
      delivery: tenant.deliveryEnabled,
    });
    let target: string | null = null;
    if (screen !== 'cart' && empty) target = hrefs.cart;
    else if ((screen === 'payment' || screen === 'review') && !details.ok) target = hrefs.checkout;
    if (target === null) return;
    redirected.current = true;
    router.replace(target);
  }, [draft, hrefs, quote, ready, router, screen, tenant.deliveryEnabled, tenant.pickupEnabled]);

  /*
   * Step navigation CARRIES the scenario switch. Without it a demo state
   * chosen on one step vanishes on the next, which makes the send failures
   * unreachable by URL and the evidence unreproducible. It is the same closed
   * allowlist either way: an unrecognised value selects nothing.
   */
  const go = useCallback(
    (href: string) => router.push(withFlowScenario(href, fx)),
    [fx, router],
  );

  /**
   * The noncontact summary of THIS send, from the same quote that priced it.
   * Ids, quantities, selections and quoted amounts only: nothing typed into a
   * contact field can reach the handoff, because the handoff type has no slot
   * for it and nothing here reads one.
   */
  const handoffFor = useCallback(
    (ref: string, kind: RequestHandoff['kind'], seen: boolean): RequestHandoff | null => {
      if (quote === null || cart === null) return null;
      return {
        slug,
        ref,
        kind,
        service: quote.service,
        zoneId: quote.zone?.id ?? '',
        zoneName: quote.feeApplies && quote.zone !== null ? quote.zone.name : null,
        lines: quote.lines.map((line) => ({
          itemId: line.item.id,
          qty: line.qty,
          selections: cart.state.lines.find((l) => l.lineId === line.lineId)?.selections ?? {},
          lineTotalMinor: line.lineTotalMinor,
        })),
        subtotalMinor: quote.subtotalMinor,
        feeMinor: quote.feeMinor,
        taxMinor: quote.taxMinor,
        totalMinor: quote.totalMinor,
        // The instant belongs to a send; a duplicate recovery invents none.
        createdAt: kind === 'accepted' ? Date.now() : null,
        seen,
      };
    },
    [cart, quote, slug],
  );

  const complete = useCallback<CompletionObserver>(
    (result) => {
      onComplete?.(result);
      if (result.kind !== 'accepted') return;
      const handoff = handoffFor(result.ref, 'accepted', false);
      if (handoff !== null) handoffApi?.set(handoff);
      // A request-route demo token on this URL rides along (fixture layer).
      router.push(withRequestScenario(requestPath(locale, result.ref), window.location.search));
    },
    [handoffApi, handoffFor, locale, onComplete, router],
  );

  const viewStatus = useCallback(
    (ref: string) => {
      const handoff = handoffFor(ref, 'duplicate', true);
      if (handoff !== null) handoffApi?.set(handoff);
      router.push(requestPath(locale, ref));
    },
    [handoffApi, handoffFor, locale, router],
  );

  /*
   * The gateway. ~900ms is the approved mocked delay (DESIGN_HANDOFF.md:130,
   * INTERACTIONS.md:94) - a timer, not I/O. Nothing is fetched, posted,
   * queued, logged or retained.
   */
  const outcome = sendOutcomeFor(fx);
  const activeGateway = useMemo(
    () => gateway ?? fixtureGateway({ outcome, delayMs: 900 }),
    [gateway, outcome],
  );

  /* Before the visitor's own cart has been read there is nothing truthful to
     draw, so only the chrome renders. The static document says the same. */
  if (!ready) {
    return <FlowSkeleton m={m} screen={screen} hrefs={hrefs} />;
  }

  // Re-evaluated on every render, so the send reads the CURRENT answer.
  const submittable =
    quote.lines.length > 0 &&
    validateCheckout(draft, quote, {
      pickup: tenant.pickupEnabled,
      delivery: tenant.deliveryEnabled,
    }).ok;

  const kind = noticeFor(fx);
  const notice: CartNotice | null =
    dismissed || kind === null
      ? null
      : {
          kind,
          // The real name of a real line, never a hard-coded demo product.
          itemName: cart.summary.lines[0]?.item.name ?? '',
        };

  switch (screen) {
    case 'cart':
      return (
        <CartScreen
          m={m}
          cart={cart}
          quote={quote}
          menuHref={hrefs.menu}
          state={state}
          opensAt={tenant.opensAt}
          motion={motion}
          notice={notice}
          pending={pending}
          onDismissNotice={() => setDismissed(true)}
          onCheckout={() => go(hrefs.checkout)}
        />
      );
    case 'checkout':
      return (
        <DetailsScreen
          m={m}
          draft={draft}
          set={draftApi?.set ?? (() => undefined)}
          quote={quote}
          tenant={tenant}
          motion={motion}
          backHref={hrefs.cart}
          pending={pending}
          onContinue={() => go(hrefs.payment)}
          onAddItems={() => go(hrefs.menu)}
        />
      );
    case 'payment':
      return (
        <PaymentScreen
          m={m}
          quote={quote}
          tenant={tenant}
          motion={motion}
          backHref={hrefs.checkout}
          pending={pending}
          onContinue={() => go(hrefs.review)}
        />
      );
    default:
      return (
        <ReviewScreen
          m={m}
          locale={locale}
          slug={slug}
          menuVersion={MENU_VERSION}
          cart={cart}
          draft={draft}
          quote={quote}
          tenant={tenant}
          motion={motion}
          backHref={hrefs.payment}
          pending={pending}
          submittable={submittable}
          gateway={activeGateway}
          onEditDetails={() => go(hrefs.checkout)}
          onEditPayment={() => go(hrefs.payment)}
          onComplete={complete}
          onViewStatus={viewStatus}
        />
      );
  }
}

/**
 * The pre-hydration frame.
 *
 * It carries the header and nothing else. A static document is identical for
 * every visitor, so anything below the header would be a cart nobody owns -
 * the same rule that keeps the prerendered dock empty.
 */
function FlowSkeleton({
  m,
  screen,
  hrefs,
}: {
  m: ReturnType<typeof storefrontMessages>;
  screen: FlowScreenName;
  hrefs: Readonly<Record<string, string>>;
}) {
  return (
    <div className={s.screen} data-sf-screen={screen} data-sf-pending="">
      {screen === 'cart' ? (
        <CartHeader m={m} backHref={hrefs.menu} count={0} />
      ) : screen === 'checkout' ? (
        <StepHeader m={m} title={m.checkout} backHref={hrefs.cart} step={0} />
      ) : screen === 'payment' ? (
        <StepHeader m={m} title={m.payment} backHref={hrefs.checkout} step={1} />
      ) : (
        <StepHeader m={m} title={m.review} backHref={hrefs.payment} step={2} />
      )}
      <div className={s.body} />
    </div>
  );
}

/** Re-exported so a test can build the same quote the screens read. */
export { buildQuote };
export type { Quote };
