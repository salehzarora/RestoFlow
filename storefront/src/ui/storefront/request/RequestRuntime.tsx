'use client';

/**
 * THE PHASE E RUNTIME - one client island for `/r/[ref]`, which is TWO views.
 *
 * WHICH VIEW. The URL says nothing about it (PACKET:309): if this document's
 * in-memory handoff names THIS ref and has not been shown yet, the visitor
 * just sent the request and sees RECEIVED; otherwise - a direct load, a
 * reload, a return visit, the duplicate recovery - the same URL renders
 * STATUS from the source. Received is shown once: choosing it marks the
 * handoff seen at that moment, so Back and Forward render status; "track
 * status" and "continue on WhatsApp" switch to status in place, as the
 * prototype's `goStatus` / `continueWa` do (:723, :731), and hand focus to
 * the status card so a keyboard or screen-reader visitor lands somewhere.
 *
 * NOTHING IS PRERENDERED. The static document is the chrome only
 * (`data-sf-pending`), identical for everyone. The handoff is read and the
 * source subscribed after hydration, so no request state, no TTL, no line and
 * no amount reaches the served bytes.
 *
 * WHY THE FIXTURE IS IMPORTED HERE. The same reasoning as FlowRuntime: a
 * fixture handed down as a prop is serialised into every document's RSC
 * payload; imported by the client it lives in one shared chunk.
 *
 * WHAT IS DELIBERATELY ABSENT: no storage of any kind, no network, no real
 * WhatsApp, no clock other than the injected one, no arithmetic (the amounts
 * are the ones the money authority quoted at send time or in the fixture).
 */
import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState } from 'react';
import { useRouter } from 'next/navigation';
import { useCart } from '@/cart/useCart';
import { optionSummary, resolveLine } from '@/cart/cartModel';
import { storefrontMessages } from '@/i18n/storefront';
import type { Locale } from '@/i18n/locales';
import { MENU_ITEMS, MENU_VERSION } from '@/source/menu-fixture';
import { demoStatusSource } from '@/source/request-fixture';
import { readRequestScenario, type RequestScenario } from '@/source/request-scenarios';
import { displayCodeFor } from '@/source/request-ref';
import type { MotionMode } from '@/source/types';
import { menuPath, requestPath } from '@/routes/routes';
import { absoluteUrl } from '@/routes/origin';
import { copyText, type CopyText } from './clipboard';
import { demoLauncher, type WhatsAppLauncher } from './launcher';
import { composeMessage, type ContentLocale } from './message';
import { useRequestHandoff, type RequestHandoff } from './RequestHandoffProvider';
import { ReceivedScreen } from './ReceivedScreen';
import { StatusScreen } from './StatusScreen';
import { DemoNote, LogoDisc, type RequestTenant, type ViewLine } from './requestParts';
import { BackLink } from '../checkout/flowParts';
import { TenantText } from '../TenantText';
import {
  isPending,
  supersedes,
  type CancelResult,
  type Clock,
  type RequestSnapshot,
  type StatusSource,
} from './status';
import s from './request.module.css';

export interface RequestProps {
  readonly locale: Locale;
  readonly requestRef: string;
  readonly slug: string;
  readonly contentLocale: ContentLocale;
  readonly tenant: RequestTenant;
  readonly motion: MotionMode;
  /** Test seams. Production passes nothing and gets the fixtures. */
  readonly statusSource?: StatusSource;
  readonly launcher?: WhatsAppLauncher;
  readonly copy?: CopyText;
  readonly clock?: Clock;
}

type View = 'pending' | 'received' | 'status';

/** Lines for either view, resolved against the menu the client already holds. */
function viewLines(
  lines: readonly { readonly itemId: string; readonly qty: number; readonly selections: RequestHandoff['lines'][number]['selections']; readonly lineTotalMinor: number }[],
): readonly ViewLine[] {
  const out: ViewLine[] = [];
  lines.forEach((line, index) => {
    const resolved = resolveLine(
      { lineId: `v${index}`, itemId: line.itemId, qty: line.qty, selections: line.selections, note: '' },
      MENU_ITEMS,
    );
    if (resolved === null) return;
    out.push({
      key: `v${index}`,
      qty: line.qty,
      name: resolved.item.name,
      options: optionSummary(resolved),
      totalMinor: line.lineTotalMinor,
    });
  });
  return out;
}

export function RequestRuntime({
  locale,
  requestRef: ref,
  slug,
  contentLocale,
  tenant,
  motion,
  statusSource,
  launcher,
  copy,
  clock,
}: RequestProps) {
  const m = storefrontMessages(locale);
  const router = useRouter();
  const handoffApi = useRequestHandoff();
  const cart = useCart(slug, MENU_VERSION, MENU_ITEMS);
  const now = useMemo<Clock>(() => clock ?? (() => Date.now()), [clock]);
  const open = launcher ?? demoLauncher;
  const doCopy = copy ?? copyText;

  // Everything below is decided AFTER hydration. The first client render is
  // the pending frame, byte for byte the static document.
  const [view, setView] = useState<View>('pending');
  const [scenario, setScenario] = useState<RequestScenario>(null);
  const [decided, setDecided] = useState(false);

  // The handoff that opened this view, captured once so that marking it seen
  // (which the provider does in place) does not change what is rendered.
  const handoffRef = useRef<RequestHandoff | null>(null);

  useLayoutEffect(() => {
    const fx = readRequestScenario(window.location.search);
    setScenario(fx);
    const h = handoffApi?.handoff ?? null;
    const mine = h !== null && h.ref === ref && h.slug === slug ? h : null;
    handoffRef.current = mine;
    const received = mine !== null && mine.kind === 'accepted' && !mine.seen;
    setView(received ? 'received' : 'status');
    // Shown once means marked seen NOW, not when the visitor leaves it: a
    // Back / Forward remount of this same document renders status. The
    // captured object above is what this mount keeps rendering.
    if (received) handoffApi?.markSeen(ref);
    setDecided(true);
    // Decided once per mount: a later handoff change must not flip the view.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [ref, slug]);

  // The source, created once the scenario and the handoff are known. One
  // instance per mount; the seed is this visitor's own send, if any.
  const source = useMemo<StatusSource | null>(() => {
    if (!decided) return null;
    if (statusSource) return statusSource;
    const h = handoffRef.current;
    return demoStatusSource({
      scenario,
      clock: now,
      seed:
        h === null
          ? undefined
          : {
              service: h.service,
              zoneId: h.zoneId,
              lines: h.lines.map((l) => ({ itemId: l.itemId, qty: l.qty, selections: l.selections })),
              createdAt: h.createdAt ?? undefined,
            },
    });
  }, [decided, now, scenario, statusSource]);

  const [snapshot, setSnapshot] = useState<RequestSnapshot | null>(null);
  const [missing, setMissing] = useState(false);
  const snapshotRef = useRef<RequestSnapshot | null>(null);
  snapshotRef.current = snapshot;

  useEffect(() => {
    if (source === null) return;
    let live = true;
    const stop = source.subscribe(
      ref,
      (next) => {
        // Stale, foreign or older answers are refused in one place, against
        // the latest QUEUED snapshot: two answers in one task cannot both
        // pass a guard that only reads the last rendered one.
        if (!live) return;
        setSnapshot((cur) => (supersedes(cur, next, ref) ? next : cur));
      },
      () => {
        if (live) setMissing(true);
      },
    );
    return () => {
      live = false;
      stop();
    };
  }, [ref, source]);

  // The clock the TTL is read against. It ticks only while a pending request
  // has an expiry, and stops the moment the source moves on.
  const [tick, setTick] = useState(() => now());
  const ticking = snapshot !== null && isPending(snapshot.state) && snapshot.expiresAt !== null;
  useEffect(() => {
    if (!ticking) return;
    setTick(now());
    const id = setInterval(() => setTick(now()), 1000);
    return () => clearInterval(id);
  }, [now, ticking]);

  const [cancelling, setCancelling] = useState(false);
  const alive = useRef(true);
  useEffect(() => {
    alive.current = true;
    return () => {
      alive.current = false;
    };
  }, []);

  const onCancel = useCallback(async () => {
    const current = snapshotRef.current;
    if (source === null || current === null || cancelling) return;
    setCancelling(true);
    // A source that throws is an unknown answer, and the sheet must not stay
    // inert forever: the flag clears on every path.
    let result: CancelResult = { kind: 'unknown' };
    try {
      result = await source.cancel(ref, current.version);
    } catch {
      result = { kind: 'unknown' };
    } finally {
      if (alive.current) setCancelling(false);
    }
    if (!alive.current) return;
    // Either answer is the truth now: cancelled, or whatever the restaurant
    // did first. An unknown answer changes nothing.
    if (result.kind !== 'unknown') {
      const answer = result.snapshot;
      setSnapshot((cur) => (supersedes(cur, answer, ref) ? answer : cur));
    }
  }, [cancelling, ref, source]);

  const hrefs = useMemo(() => ({ menu: menuPath(locale, slug) }), [locale, slug]);

  // Whether the status view was reached by an in-place switch from received:
  // the activated control unmounts, so the status card takes focus instead.
  const switched = useRef(false);
  const goStatus = useCallback(() => {
    handoffApi?.markSeen(ref);
    switched.current = true;
    setView('status');
  }, [handoffApi, ref]);

  const h = handoffRef.current;
  // The code is request data, never a prerendered fact: the status view reads
  // the source's, the received view the fixture's, both after mount.
  const displayCode = snapshot?.displayCode ?? displayCodeFor(ref) ?? '';
  const receivedLines = useMemo(() => (h === null ? [] : viewLines(h.lines)), [h]);
  const message = useMemo(() => {
    if (h === null) return '';
    return composeMessage({
      contentLocale,
      displayCode,
      restaurantName: tenant.name,
      lines: receivedLines.map((l) => ({ qty: l.qty, name: l.name, options: l.options })),
      totalMinor: h.totalMinor,
      service: h.service,
      zoneName: h.zoneName,
      // The restaurant reads the link, so it is built for the content language.
      statusUrl: absoluteUrl(requestPath('ar', ref)),
    });
  }, [contentLocale, displayCode, h, receivedLines, ref, tenant.name]);

  const onContinue = useCallback(() => {
    // DEFERRED(WA-001): the demo launcher opens nothing and says so.
    open.open('', message);
    goStatus();
  }, [goStatus, message, open]);

  const onChat = useCallback(() => {
    open.open('', '');
  }, [open]);

  const onWaWeb = useCallback(() => {
    open.open('', message);
  }, [message, open]);

  const onOrderAgain = useCallback(() => {
    // INTERACTIONS.md:115 - the ONE designed clear: empties the cart on this
    // device and returns to the menu. Nothing else ever clears a cart.
    cart.clear();
    handoffApi?.clear();
    router.push(hrefs.menu);
  }, [cart, handoffApi, hrefs.menu, router]);

  const motionFull = motion !== 'calm';
  const statusLines = useMemo(() => (snapshot === null ? [] : viewLines(snapshot.lines)), [snapshot]);

  if (view === 'pending' || !decided) {
    return <RequestSkeleton m={m} tenant={tenant} menuHref={hrefs.menu} />;
  }

  if (view === 'received' && h !== null) {
    return (
      <>
        <DemoNote m={m} />
        <ReceivedScreen
          m={m}
          tenant={tenant}
          displayCode={displayCode}
          service={h.service}
          lines={receivedLines}
          totalMinor={h.totalMinor}
          message={message}
          fallback={scenario?.kind === 'fallback'}
          motionFull={motionFull}
          copy={doCopy}
          onContinue={onContinue}
          onTrack={goStatus}
          onWaWeb={onWaWeb}
        />
      </>
    );
  }

  if (missing) {
    return (
      <>
        <DemoNote m={m} />
        <div className={s.screen} data-sf-screen="status" data-sf-status="missing">
          <header className={s.head}>
            <BackLink href={hrefs.menu} label={m.back} />
            <LogoDisc tenant={tenant} small />
            <div className={s.headText}>
              <div className={s.headSub}>
                <TenantText>{tenant.name}</TenantText>
              </div>
            </div>
          </header>
          <div className={s.missing} role="status">
            <h1 className={s.missingTitle}>{m.unknownTitle}</h1>
            <p className={s.missingBody}>{m.unknownBody}</p>
          </div>
        </div>
      </>
    );
  }

  if (snapshot === null) {
    return <RequestSkeleton m={m} tenant={tenant} menuHref={hrefs.menu} />;
  }

  return (
    <>
      <DemoNote m={m} />
      <StatusScreen
        m={m}
        tenant={tenant}
        snapshot={snapshot}
        lines={statusLines}
        now={tick}
        menuHref={hrefs.menu}
        motionFull={motionFull}
        cancelling={cancelling}
        focusOnMount={switched.current}
        onChat={onChat}
        onCancel={onCancel}
        onOrderAgain={onOrderAgain}
      />
    </>
  );
}

/**
 * The pre-hydration frame, and the frame while the source has not answered:
 * the status header's chrome (back, logo, restaurant name) and nothing that
 * belongs to a request - no code, no state, no line, no amount.
 */
function RequestSkeleton({
  m,
  tenant,
  menuHref,
}: {
  m: ReturnType<typeof storefrontMessages>;
  tenant: RequestTenant;
  menuHref: string;
}) {
  return (
    <div className={s.screen} data-sf-screen="request" data-sf-pending="">
      <header className={s.head}>
        <BackLink href={menuHref} label={m.back} />
        <LogoDisc tenant={tenant} small />
        <div className={s.headText}>
          <div className={s.headSub}>
            <TenantText>{tenant.name}</TenantText>
          </div>
        </div>
      </header>
      <div className={s.pendingBody} />
    </div>
  );
}
