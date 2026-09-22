'use client';

/**
 * STEP 3 OF 3 - REVIEW AND SEND.
 *
 * Line summary with `qty x`, totals, then the receive / contact / payment
 * blocks each with an Edit link back to the step that owns the field. An info
 * notice states that sending SAVES the request and OPENS WhatsApp, and that
 * nothing is confirmed until the restaurant accepts (DESIGN_HANDOFF.md:130).
 *
 * A SUBMISSION IS A PENDING REQUEST, NEVER AN ORDER (README.md:46). The copy
 * says "saving", not "sending", and this screen never claims a message was
 * sent.
 *
 * FAILURE PRESERVES EVERYTHING. The cart is untouched, the draft is untouched,
 * the scroll position and all three blocks are untouched, and nothing is
 * written anywhere. Each failure carries ONE recovery.
 *
 * THE D/E BOUNDARY. Phase D owns the typed RESULT of a send. The received
 * screen at `/r/:ref` is Phase E and does not exist yet, so an accepted send
 * hands the result to an injected observer instead of navigating to a route
 * that would 404.
 */
import { useCallback, useEffect, useRef, useState, type ReactNode } from 'react';
import type { CartApi } from '@/cart/useCart';
import { optionSummary } from '@/cart/cartModel';
import { fill, type StorefrontMessages } from '@/i18n/storefront';
import { formatMoney } from '@/money/format';
import type { Quote } from '@/money/quote';
import type { Locale } from '@/i18n/locales';
import type { MotionMode } from '@/source/types';
import type { CheckoutDraft } from './CheckoutDraftProvider';
import {
  buildSubmission,
  newIdempotencyKey,
  type CompletionObserver,
  type RequestGateway,
  type SubmitResult,
} from './submit';
import type { FlowTenant } from './DetailsScreen';
import {
  AlertIcon,
  CardIcon,
  ClockIcon,
  DuplicateIcon,
  InfoIcon,
  OfflineIcon,
  PersonIcon,
  PinIcon,
  SendIcon,
} from '../icons';
import { TenantText } from '../TenantText';
import { Banner, Bidi, FooterCta, Interpolate, StepHeader, Totals } from './flowParts';
import s from './flow.module.css';

/**
 * The address joiner.
 *
 * The prototype hard-codes the Arabic comma U+060C (:828), which is wrong
 * punctuation in Hebrew and English. The separator is typography, not copy, so
 * it follows the page's language rather than being frozen with the Arabic
 * text. Recorded as a deviation.
 */
function commaFor(locale: Locale): string {
  return locale === 'ar' ? '، ' : ', ';
}

function addressOf(draft: CheckoutDraft, zoneName: string, locale: Locale): string {
  const building = `${draft.street} ${draft.building}`.trim();
  return [zoneName, draft.area, building, draft.apartment]
    .map((part) => part.trim())
    .filter((part) => part !== '')
    .join(commaFor(locale));
}

function ReviewBlock({
  icon,
  label,
  value,
  sub,
  foot,
  editLabel,
  editName,
  onEdit,
  testId,
}: {
  icon: ReactNode;
  label: string;
  value: ReactNode;
  sub?: ReactNode;
  foot?: string;
  /** The one approved word. */
  editLabel: string;
  /** The same word plus the step it returns to, for the accessible name. */
  editName: string;
  onEdit: () => void;
  testId: string;
}) {
  return (
    <div className={s.block} data-sf-block={testId}>
      <span className={s.blockTile} aria-hidden="true">
        {icon}
      </span>
      <div className={s.blockText}>
        <div className={s.blockLabel}>{label}</div>
        <div className={s.blockValue}>{value}</div>
        {sub === undefined ? null : <div className={s.blockSub}>{sub}</div>}
        {foot === undefined ? null : <div className={s.blockFoot}>{foot}</div>}
      </div>
      {/* The Edit control NAMES its destination, so "Edit" heard three times
          in a row is still three distinct actions. */}
      <button
        className={s.blockEdit}
        type="button"
        onClick={onEdit}
        aria-label={editName}
        data-sf-edit={testId}
      >
        {/* The VISIBLE label stays the approved single word. */}
        <span aria-hidden="true">{editLabel}</span>
      </button>
    </div>
  );
}

export function ReviewScreen({
  m,
  locale,
  slug,
  menuVersion,
  cart,
  draft,
  quote,
  tenant,
  motion,
  backHref,
  pending,
  gateway,
  onEditDetails,
  onEditPayment,
  onComplete,
}: {
  m: StorefrontMessages;
  locale: Locale;
  slug: string;
  menuVersion: string;
  cart: CartApi;
  draft: CheckoutDraft;
  quote: Quote;
  tenant: FlowTenant;
  motion: MotionMode;
  backHref: string;
  /** True while the quote for the CURRENT cart has not arrived. */
  pending: boolean;
  gateway: RequestGateway;
  onEditDetails: () => void;
  onEditPayment: () => void;
  onComplete: CompletionObserver;
}) {
  const [sending, setSending] = useState(false);
  const [failure, setFailure] = useState<SubmitResult | null>(null);

  /*
   * ONE ATTEMPT AT A TIME, AND NO STALE COMPLETION.
   *
   * `attempt` is bumped for every send. A resolution whose sequence is not the
   * current one - a completion that lands after the component unmounted, after
   * the route changed, or after a newer attempt started - is DISCARDED: no
   * state update, no navigation. Nothing in the approved pack specifies this;
   * it is a correctness requirement the mock hides by never failing slowly.
   */
  const attempt = useRef(0);
  const alive = useRef(true);
  useEffect(() => {
    alive.current = true;
    return () => {
      alive.current = false;
    };
  }, []);

  // DEFERRED(IDEM-001): minted ONCE per mount and reused by every retry, so a
  // retry is the same request rather than a second one.
  const key = useRef('');
  if (key.current === '') key.current = newIdempotencyKey();

  const isDelivery = quote.service === 'delivery';
  const zoneName = quote.zone?.name ?? '';

  const send = useCallback(() => {
    // Nothing may be sent against a total that does not belong to this cart.
    if (sending || pending) return;
    const mine = attempt.current + 1;
    attempt.current = mine;
    setFailure(null);
    setSending(true);
    void (async () => {
      let result: SubmitResult;
      try {
        result = await gateway(
          buildSubmission(slug, menuVersion, quote, draft, key.current),
        );
      } catch {
        result = { kind: 'server_error' };
      }
      if (!alive.current || attempt.current !== mine) return;
      setSending(false);
      if (result.kind === 'accepted') {
        onComplete(result);
        return;
      }
      // A duplicate is also something Phase E owns a destination for, so the
      // observer learns the reference even though this phase renders no
      // navigation for it. Reported HERE, in the handler, never during render.
      if (result.kind === 'duplicate') onComplete(result);
      // `cart_changed` is DEFERRED(SNAP-001): the packet types it, the handoff
      // designs no banner for it and the pack carries no copy. It is left
      // unrendered rather than given an invented fifth banner.
      setFailure(result);
    })();
  }, [draft, gateway, menuVersion, onComplete, pending, quote, sending, slug]);

  const banner = failure === null ? null : bannerFor(failure, m, send);

  return (
    <div className={`${s.screen} ${motion === 'calm' ? '' : s.motionFull}`} data-sf-screen="review">
      <StepHeader m={m} title={m.review} backHref={backHref} step={2} />

      <div className={`${s.body} ${s.bodySteps}`}>
        <div className={s.summary}>
          <ul className={s.summaryList}>
            {cart.summary.lines.map((line) => {
              const mods = optionSummary(line);
              return (
                <li className={s.summaryLine} key={line.line.lineId}>
                  <span className={`${s.qtyChip} ${s.ltr}`} dir="ltr">
                    {`${line.line.qty}×`}
                  </span>
                  <span className={s.summaryText}>
                    <span className={s.summaryName}>
                      <TenantText>{line.item.name}</TenantText>
                    </span>
                    {mods === '' ? null : (
                      <span className={s.summaryMods}>
                        <TenantText>{mods}</TenantText>
                      </span>
                    )}
                    {line.line.note === '' ? null : (
                      <span className={s.summaryNote}>
                        <TenantText>{line.line.note}</TenantText>
                      </span>
                    )}
                  </span>
                  <span className={`${s.summaryPrice} ${s.ltr}`} dir="ltr">
                    {formatMoney(line.totalMinor)}
                  </span>
                </li>
              );
            })}
          </ul>
          <Totals quote={quote} m={m} bare />
        </div>

        <div className={s.blocks}>
          <ReviewBlock
            icon={<PinIcon />}
            label={m.receive}
            value={isDelivery ? m.delivery : fill(m.pickupAt, { r: tenant.name })}
            sub={
              <TenantText>
                {isDelivery ? addressOf(draft, zoneName, locale) : tenant.address}
              </TenantText>
            }
            foot={m.restaurantConfirms}
            editLabel={m.edit}
            editName={`${m.edit} · ${m.stepDetails}`}
            onEdit={onEditDetails}
            testId="receive"
          />
          <ReviewBlock
            icon={<PersonIcon />}
            label={m.customer}
            value={<Bidi>{draft.fullName}</Bidi>}
            sub={
              <span className={s.ltr} dir="ltr">
                {draft.phone}
              </span>
            }
            editLabel={m.edit}
            editName={`${m.edit} · ${m.stepDetails}`}
            onEdit={onEditDetails}
            testId="contact"
          />
          <ReviewBlock
            icon={<CardIcon />}
            label={m.payment}
            value={m.cash}
            sub={isDelivery ? m.cashDelivery : m.cashPickup}
            editLabel={m.edit}
            editName={`${m.edit} · ${m.stepPayment}`}
            onEdit={onEditPayment}
            testId="payment"
          />
        </div>

        {/* Always present, never an action: the truth notice. */}
        <Banner
          tone="info"
          alert={false}
          smallIcon
          icon={<InfoIcon />}
          title={
            <Interpolate template={m.sendInfo} values={{ r: <Bidi>{tenant.name}</Bidi> }} />
          }
          testId="truth-notice"
        />

        {/* The failure banner sits between the truth notice and the footer. */}
        {banner}
      </div>

      <FooterCta
        label={sending ? m.sending : m.sendRequest}
        onActivate={send}
        busy={sending}
        blocked={pending}
        live={motion !== 'calm'}
        centred
        leading={
          sending ? (
            <span className={s.spinner} aria-hidden="true" />
          ) : (
            <span className={s.ctaIcon} aria-hidden="true">
              <SendIcon />
            </span>
          )
        }
        testId="send"
      />
    </div>
  );
}

/**
 * One banner per failure, each with exactly ONE recovery.
 *
 * The test hooks are the TYPED kinds (`server_error`, `rate_limited`), not the
 * hyphenated demo tokens that select them: the banner belongs to the result,
 * and the token that produced it is fixture machinery this screen never sees.
 *
 * `duplicate` deliberately has NO action in this phase. Its designed recovery
 * is "view status", which goes to `/r/:ref` - a Phase E route that does not
 * exist. An enabled control whose only outcome is a 404 is worse than none, so
 * the action is withheld and the body still tells the visitor what to do.
 */
function bannerFor(result: SubmitResult, m: StorefrontMessages, retry: () => void) {
  const retryAction = { label: m.retry, onAction: retry, solid: true };
  switch (result.kind) {
    case 'offline':
      return (
        <Banner
          tone="warn"
          shake
          icon={<OfflineIcon />}
          title={m.offline}
          body={m.offlineBody}
          action={retryAction}
          testId="offline"
        />
      );
    case 'server_error':
      return (
        <Banner
          tone="bad"
          shake
          icon={<AlertIcon />}
          title={m.serverError}
          body={m.serverBody}
          action={retryAction}
          testId="server_error"
        />
      );
    case 'rate_limited':
      return (
        <Banner
          tone="warn"
          shake
          icon={<ClockIcon />}
          title={m.rateLimited}
          body={m.rateBody}
          action={retryAction}
          testId="rate_limited"
        />
      );
    case 'duplicate':
      return (
        <Banner
          tone="info"
          shake
          icon={<DuplicateIcon />}
          title={m.duplicate}
          body={m.duplicateBody}
          testId="duplicate"
        />
      );
    default:
      return null;
  }
}
