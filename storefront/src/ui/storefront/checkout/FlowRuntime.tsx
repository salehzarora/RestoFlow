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
 * call, no analytics, no WhatsApp, no `/r/:ref` navigation. Phase D ends at the
 * typed result of a send.
 */
import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState } from 'react';
import { useRouter } from 'next/navigation';
import { useCartApi } from '../cart/CartRuntime';
import { StorefrontRuntime } from '../StorefrontRuntime';
import { storefrontMessages } from '@/i18n/storefront';
import type { Locale } from '@/i18n/locales';
import { buildQuote, type Quote, type QuoteInput } from '@/money/quote';
import { delayedQuoteSource, useQuote, type QuoteSource } from '@/money/useQuote';
import { MENU_ITEMS, MENU_VERSION, TAX_RATE } from '@/source/menu-fixture';
import { findZone } from '@/source/zones';
import {
  isQuoteRace,
  noticeFor,
  readFlowScenario,
  sendOutcomeFor,
  withFlowScenario,
} from '@/source/flow-scenarios';
import type { MotionMode, ServiceState } from '@/source/types';
import { cartPath, checkoutPath, menuPath, paymentPath, reviewPath } from '@/routes/routes';
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

/**
 * The race seam's SOURCE.
 *
 * WHICH scenario selects it is the fixture layer's decision; HOW it behaves is
 * a quote concern and belongs beside the quote. It makes a SMALLER cart resolve
 * more slowly, so an older request always lands after a newer one - the only
 * failure mode an async quote really has, and one that cannot be reproduced by
 * timing luck. It changes nothing but WHEN a result arrives: the arithmetic,
 * the inputs and the rendered figures are the fixture's own.
 */
const RACE_QUOTE: QuoteSource = delayedQuoteSource((input) => {
  const units = input.cart.lines.reduce((n, l) => n + l.qty, 0);
  return Math.max(120, 1600 - units * 120);
});

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
      m={m}
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
  const source = quoteSource ?? (isQuoteRace(fx) ? RACE_QUOTE : undefined);
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
    const details = validateCheckout(draft, quote);
    let target: string | null = null;
    if (screen !== 'cart' && empty) target = hrefs.cart;
    else if ((screen === 'payment' || screen === 'review') && !details.ok) target = hrefs.checkout;
    if (target === null) return;
    redirected.current = true;
    router.replace(target);
  }, [draft, hrefs, quote, ready, router, screen]);

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

  const complete = useCallback<CompletionObserver>(
    (result) => {
      onComplete?.(result);
    },
    [onComplete],
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
          gateway={activeGateway}
          onEditDetails={() => go(hrefs.checkout)}
          onEditPayment={() => go(hrefs.payment)}
          onComplete={complete}
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
