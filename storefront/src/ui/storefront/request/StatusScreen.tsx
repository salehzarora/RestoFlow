'use client';

/**
 * S10 STATUS - what the SOURCE says, and nothing it did not say.
 *
 * Header (:549-:552), the status hero card with its tone (:554-:557), the
 * vertical timeline (:558-:565), the per-state action set (:566-:570), the
 * order summary (:571) and the cancel confirmation sheet (:573-:576). Every
 * per-state choice comes from STATE_TABLE in status.ts - one table - and every
 * clock reading on the timeline comes from a recorded event.
 *
 * THE TTL LIVES OUTSIDE THE LIVE REGION. The prototype puts the per-second
 * countdown inside `role="status" aria-live="polite"`, which would announce
 * every tick. The title and body are the live region; the pill is a sibling
 * `role="timer"` with `aria-live="off"` (PACKET PX-5c), and an LTR island.
 *
 * NOTHING IS INVENTED: no ETA, no courier, no "ready in N minutes", no rating.
 * A restaurant that has not answered is "waiting", and a request the source
 * calls expired is expired - the screen never promotes or demotes a state on
 * its own.
 */
import { useCallback, useEffect, useId, useRef, useState, type KeyboardEvent, type ReactNode } from 'react';
import { fill, type StorefrontMessages } from '@/i18n/storefront';
import { BackLink, Bidi, Interpolate } from '../checkout/flowParts';
import { TenantText } from '../TenantText';
import { CheckIcon, LineRows, LogoDisc, WhatsAppGlyph, type RequestTenant, type ViewLine } from './requestParts';
import {
  STATE_TABLE,
  timelineFor,
  ttlFor,
  type RequestSnapshot,
  type RequestState,
  type StatusTone,
  type TimelineNode,
} from './status';
import s from './request.module.css';

const TONE_CLASS: Readonly<Record<StatusTone, string>> = {
  info: s.toneInfo,
  warn: s.toneWarn,
  ok: s.toneOk,
  bad: s.toneBad,
  neutral: s.toneNeutral,
};

/** The hero-card icons (:840). A check for received / accepted / completed. */
const ICON_PATH: Readonly<Record<RequestState, string>> = {
  received: 'M5 12l5 5L20 7',
  waiting: 'M12 7v5l3 2M3 12a9 9 0 1018 0 9 9 0 10-18 0z',
  accepted: 'M5 12l5 5L20 7',
  preparing: 'M4 14h16v6H4zM6 14V9a6 6 0 0112 0v5M12 3v2',
  ready: 'M20 7L9 18l-5-5',
  completed: 'M5 12l5 5L20 7',
  rejected: 'M6 6l12 12M18 6L6 18',
  expired: 'M12 7v5l3 2M3 12a9 9 0 1018 0 9 9 0 10-18 0z',
  cancelled: 'M6 6l12 12M18 6L6 18',
};

function PathIcon({ d }: { d: string }) {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true" focusable="false">
      <path d={d} />
    </svg>
  );
}

/** Times are 24-hour HH:MM, LTR, tabular (CONTENT:234, :842 en-GB). */
function clockText(at: number): string {
  const d = new Date(at);
  return `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`;
}

/**
 * The hero title and body TEMPLATE per state (:837). The body is interpolated
 * at render so the restaurant's name sits in a <bdi> and the minute count in
 * an LTR island, rather than being flattened into the sentence.
 */
function copyFor(
  state: RequestState,
  m: StorefrontMessages,
  service: 'pickup' | 'delivery',
): { title: string; body: string } {
  switch (state) {
    case 'received':
      return { title: m.received, body: m.receivedBody };
    case 'waiting':
      return { title: m.waiting, body: m.waitingBody };
    case 'accepted':
      return { title: m.accepted, body: m.acceptedBody };
    case 'preparing':
      return { title: m.preparing, body: m.preparingBody };
    case 'ready':
      return service === 'delivery'
        ? { title: m.readyDelivery, body: m.readyDeliveryBody }
        : { title: m.readyPickup, body: m.readyPickupBody };
    case 'completed':
      return { title: m.completed, body: m.completedBody };
    case 'rejected':
      return { title: m.rejected, body: m.rejectedBody };
    case 'expired':
      return { title: m.expired, body: m.expiredBody };
    default:
      return { title: m.cancelled, body: m.cancelledBody };
  }
}

/** Timeline node labels (:841); the terminal node carries the hero title. */
function nodeLabel(node: TimelineNode, m: StorefrontMessages, service: 'pickup' | 'delivery', heroTitle: string): string {
  if (node.kind === 'terminal') return heroTitle;
  switch (node.state) {
    case 'received':
      return m.stReceived;
    case 'waiting':
      return m.stWaiting;
    case 'accepted':
      return m.stAccepted;
    case 'preparing':
      return m.stPreparing;
    case 'ready':
      return service === 'delivery' ? m.readyDelivery : m.stReady;
    default:
      return m.stCompleted;
  }
}

const NODE_CLASS: Readonly<Record<TimelineNode['kind'], string>> = {
  done: s.nodeDone,
  current: s.nodeCurrent,
  future: '',
  terminal: s.nodeTerminal,
};

export function StatusScreen({
  m,
  tenant,
  snapshot,
  lines,
  now,
  menuHref,
  motionFull,
  cancelling,
  onChat,
  onCancel,
  onOrderAgain,
}: {
  m: StorefrontMessages;
  tenant: RequestTenant;
  snapshot: RequestSnapshot;
  lines: readonly ViewLine[];
  /** The injected instant the TTL is computed against. */
  now: number;
  menuHref: string;
  motionFull: boolean;
  /** A cancel is in flight: the sheet's confirm is inert until it answers. */
  cancelling: boolean;
  onChat: () => void;
  /** Resolves once the source has answered; the sheet closes on either answer. */
  onCancel: () => Promise<void>;
  onOrderAgain: () => void;
}) {
  const row = STATE_TABLE[snapshot.state];
  const { title, body } = copyFor(snapshot.state, m, snapshot.service);
  // The slots the state bodies use (:836-:837): {r} restaurant, {m} minutes,
  // {p} the pay phrase. Unused slots are simply not referenced by a template.
  const slots: Readonly<Record<string, ReactNode>> = {
    r: <Bidi>{tenant.name}</Bidi>,
    m: (
      <span className={s.ltr} dir="ltr">
        {fill('{n} {u}', { n: String(snapshot.ttlMinutes), u: m.min })}
      </span>
    ),
    p: snapshot.service === 'delivery' ? m.payOnDelivery : m.payAtPickup,
  };
  const ttl = ttlFor(snapshot, now);
  const nodes = timelineFor(snapshot);
  const tone = TONE_CLASS[row.tone];
  const serviceLabel = snapshot.service === 'delivery' ? m.delivery : m.pickup;

  const [sheetOpen, setSheetOpen] = useState(false);
  const cancelButton = useRef<HTMLButtonElement>(null);
  const openSheet = () => setSheetOpen(true);
  const closeSheet = useCallback(() => {
    setSheetOpen(false);
    // Focus returns to the control that opened the sheet, if it still exists.
    cancelButton.current?.focus();
  }, []);

  // The sheet closes itself if the source moves on while it is open: there is
  // nothing left to cancel, and the card already says what happened.
  useEffect(() => {
    if (sheetOpen && !row.pending) setSheetOpen(false);
  }, [row.pending, sheetOpen]);

  const confirmCancel = async () => {
    if (cancelling) return;
    await onCancel();
    closeSheet();
  };

  return (
    <div className={`${s.screen} ${motionFull ? s.motionFull : ''}`} data-sf-screen="status" data-sf-status={snapshot.state}>
      <header className={s.head}>
        <BackLink href={menuHref} label={m.back} />
        <LogoDisc tenant={tenant} small />
        <div className={s.headText}>
          <div className={s.headCode}>
            <span className={s.ltr} dir="ltr" data-sf-request-code="">
              {snapshot.displayCode}
            </span>
          </div>
          <div className={s.headSub}>
            <TenantText>{tenant.name}</TenantText> &middot; {serviceLabel}
          </div>
        </div>
      </header>

      <div className={s.body}>
        <div className={`${s.card} ${tone}`} data-sf-status-card={row.tone}>
          <span className={s.cardIcon} aria-hidden="true">
            <PathIcon d={ICON_PATH[snapshot.state]} />
          </span>
          <div className={s.cardText}>
            {/* The live region: a state change announces once. */}
            <div role="status" aria-live="polite" data-sf-status-live="">
              <h1 className={s.cardTitle}>{title}</h1>
              <p className={s.cardBody}>
                <Interpolate template={body} values={slots} />
              </p>
            </div>
            {/* The countdown, outside the live region: it must not announce
                every second. Only the waiting state renders it. */}
            {ttl === null ? null : (
              <div className={s.ttl} role="timer" aria-live="off" data-sf-ttl="">
                <svg viewBox="0 0 24 24" aria-hidden="true" focusable="false">
                  <circle cx="12" cy="12" r="9" />
                  <path d="M12 7v5l3 2" />
                </svg>
                <span>
                  <Interpolate
                    template={m.expiresIn}
                    values={{
                      m: (
                        <span className={s.ltr} dir="ltr" data-sf-ttl-value="">
                          {ttl.text}
                        </span>
                      ),
                    }}
                  />
                </span>
              </div>
            )}
          </div>
        </div>

        <ol className={s.timeline} data-sf-timeline="">
          {nodes.map((node) => (
            <li
              className={`${s.node} ${NODE_CLASS[node.kind]} ${node.kind === 'terminal' ? tone : ''}`}
              key={node.state}
              aria-current={node.kind === 'current' ? 'step' : undefined}
              data-sf-node={node.state}
              data-sf-node-kind={node.kind}
            >
              <span className={s.nodeRail} aria-hidden="true">
                <span className={s.nodeDot}>
                  {node.kind === 'done' ? <CheckIcon /> : <PathIcon d={ICON_PATH[node.state]} />}
                </span>
                <span className={s.nodeLine} />
              </span>
              <span className={s.nodeText}>
                <span>
                  <span className={s.nodeLabel}>{nodeLabel(node, m, snapshot.service, title)}</span>
                  {node.countdown && ttl !== null ? (
                    <span className={s.nodeSub} data-sf-node-countdown="">
                      <Interpolate
                        template={m.expiresIn}
                        values={{
                          m: (
                            <span className={s.ltr} dir="ltr">
                              {ttl.text}
                            </span>
                          ),
                        }}
                      />
                    </span>
                  ) : null}
                </span>
                {node.at === null ? null : (
                  <span className={`${s.nodeTime} ${s.ltr}`} dir="ltr" data-sf-node-time="">
                    {clockText(node.at)}
                  </span>
                )}
              </span>
            </li>
          ))}
        </ol>

        <div className={s.actions} data-sf-status-actions={row.actions.join(' ')}>
          {row.actions.includes('chat') && row.actions.includes('cancel') ? (
            <>
              <button className={s.chatCta} type="button" onClick={onChat} data-sf-status-action="chat">
                <WhatsAppGlyph />
                {m.openChat}
              </button>
              <button
                className={s.cancelBtn}
                type="button"
                onClick={openSheet}
                ref={cancelButton}
                data-sf-status-action="cancel"
              >
                {m.cancelRequest}
              </button>
            </>
          ) : null}
          {row.actions.includes('chat') && !row.actions.includes('cancel') ? (
            <button className={s.chatOutline} type="button" onClick={onChat} data-sf-status-action="chat">
              {m.openChat}
            </button>
          ) : null}
          {row.actions.includes('orderAgain') ? (
            <button className={s.againCta} type="button" onClick={onOrderAgain} data-sf-status-action="orderAgain">
              {m.orderAgain}
            </button>
          ) : null}
        </div>

        <div className={s.statusSummary} data-sf-request-summary="">
          <LineRows lines={lines} totalMinor={snapshot.totalMinor} m={m} variant="status" />
        </div>
      </div>

      {sheetOpen ? (
        <CancelSheet
          m={m}
          restaurant={tenant.name}
          busy={cancelling}
          onKeep={closeSheet}
          onConfirm={() => void confirmCancel()}
        />
      ) : null}
    </div>
  );
}

/**
 * The confirmation sheet (:573-:576): a modal dialog. Focus moves to "keep"
 * on open, Tab cycles inside it, Escape and the scrim keep the request, and
 * focus returns to the cancel control on close. Under reduced motion the root
 * rule collapses its rise to one frame.
 */
function CancelSheet({
  m,
  restaurant,
  busy,
  onKeep,
  onConfirm,
}: {
  m: StorefrontMessages;
  restaurant: string;
  busy: boolean;
  onKeep: () => void;
  onConfirm: () => void;
}) {
  const titleId = useId();
  const bodyId = useId();
  const keep = useRef<HTMLButtonElement>(null);
  const yes = useRef<HTMLButtonElement>(null);

  useEffect(() => {
    keep.current?.focus();
  }, []);

  const onKeyDown = (event: KeyboardEvent<HTMLDivElement>) => {
    if (event.key === 'Escape') {
      event.preventDefault();
      onKeep();
      return;
    }
    if (event.key !== 'Tab') return;
    const first = keep.current;
    const last = yes.current;
    if (!first || !last) return;
    if (event.shiftKey && document.activeElement === first) {
      event.preventDefault();
      last.focus();
    } else if (!event.shiftKey && document.activeElement === last) {
      event.preventDefault();
      first.focus();
    }
  };

  return (
    <div className={s.overlay} data-sf-cancel-sheet="">
      <div className={s.scrim} onClick={onKeep} aria-hidden="true" data-sf-cancel-scrim="" />
      <div
        className={s.sheet}
        role="dialog"
        aria-modal="true"
        aria-labelledby={titleId}
        aria-describedby={bodyId}
        onKeyDown={onKeyDown}
      >
        <span className={s.handle} aria-hidden="true" />
        <h2 className={s.sheetTitle} id={titleId}>
          {m.cancelTitle}
        </h2>
        <p className={s.sheetBody} id={bodyId}>
          <Interpolate template={m.cancelBody} values={{ r: <Bidi>{restaurant}</Bidi> }} />
        </p>
        <div className={s.sheetActions}>
          <button className={s.keepBtn} type="button" onClick={onKeep} ref={keep} data-sf-cancel="keep">
            {m.keep}
          </button>
          <button
            className={s.yesBtn}
            type="button"
            onClick={onConfirm}
            ref={yes}
            aria-disabled={busy ? 'true' : undefined}
            data-sf-cancel="yes"
          >
            {m.yesCancel}
          </button>
        </div>
      </div>
    </div>
  );
}
