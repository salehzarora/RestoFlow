'use client';

/**
 * SHARED PIECES OF THE PHASE D FLOW.
 *
 * One InlineBanner, one TotalsBlock, one step header, one money island - used
 * by the cart, the three checkout steps and the wide aside, so those five
 * surfaces cannot drift apart.
 *
 * THE TOTALS BLOCK RENDERS WHATEVER THE QUOTE SAYS. It never computes tax, a
 * fee or a total; src/money/quote.ts is the single authority
 * (PACKET:589 "TotalsBlock renders whatever the Quote says; it never computes
 * tax", and the packet's own stop condition is "tax logic leaking into a
 * component").
 */
import Link from 'next/link';
import type { ReactNode } from 'react';
import { fill, type StorefrontMessages } from '@/i18n/storefront';
import { formatMoney } from '@/money/format';
import type { Quote } from '@/money/quote';
import { ChevronIcon } from '../icons';
import { TenantText } from '../TenantText';
import s from './flow.module.css';

/** The banner tones the approved inventory lists (COMPONENT_INVENTORY.md:149). */
export type Tone = 'warn' | 'bad' | 'info' | 'acc' | 'plain';

const TONE_CLASS: Readonly<Record<Tone, string>> = {
  warn: s.noticeWarn,
  bad: s.noticeBad,
  info: s.noticeInfo,
  acc: s.noticeAcc,
  plain: s.noticePlain,
};

/** A money run is always an LTR island with tabular figures. */
export function Money({ minor }: { minor: number }) {
  return (
    <span className={s.ltr} dir="ltr">
      {formatMoney(minor)}
    </span>
  );
}

/**
 * The one InlineBanner. It carries AT MOST ONE action
 * (COMPONENT_INVENTORY.md:149) - never a second dismiss button beside a
 * recovery, and never two recoveries.
 */
export function Banner({
  tone,
  icon,
  title,
  body,
  action,
  smallIcon = false,
  shake = false,
  alert = true,
  testId,
}: {
  tone: Tone;
  icon: ReactNode;
  title: ReactNode;
  body?: ReactNode;
  action?: { readonly label: string; readonly onAction: () => void; readonly solid?: boolean };
  smallIcon?: boolean;
  shake?: boolean;
  alert?: boolean;
  testId?: string;
}) {
  return (
    <div
      className={`${s.notice} ${TONE_CLASS[tone]} ${shake ? s.noticeShake : ''}`}
      role={alert ? 'alert' : undefined}
      /* A blocked tap moves FOCUS to the first problem, and a plain <div> is
         not focusable. -1 keeps it out of the tab order but reachable. */
      tabIndex={alert ? -1 : undefined}
      data-sf-banner={testId}
      data-sf-tone={tone}
    >
      <span className={`${s.noticeIcon} ${smallIcon ? s.noticeIconSm : ''}`} aria-hidden="true">
        {icon}
      </span>
      <div className={s.noticeText}>
        <div className={s.noticeTitle}>{title}</div>
        {body === undefined ? null : <div className={s.noticeBody}>{body}</div>}
        {action === undefined ? null : (
          <button
            className={`${s.noticeAction} ${action.solid === true ? s.noticeActionSolid : ''}`}
            type="button"
            onClick={action.onAction}
            data-sf-banner-action=""
          >
            <span>{action.label}</span>
          </button>
        )}
      </div>
    </div>
  );
}

/**
 * Subtotal, delivery fee, tax, total.
 *
 * The fee row renders ONLY for a served zone on delivery - `quote.feeApplies`.
 * A pickup order, an unchosen town and an unserved town all render NO fee row
 * at all rather than "0", because a zero fee would read as free delivery
 * (DESIGN_HANDOFF.md:114 "only once a zone is known").
 */
export function Totals({
  quote,
  m,
  bare = false,
}: {
  quote: Quote;
  m: StorefrontMessages;
  bare?: boolean;
}) {
  return (
    <div className={`${s.totals} ${bare ? s.totalsBare : ''}`} data-sf-totals="">
      <div className={s.totalRow}>
        <span className={s.totalLabel}>{m.subtotal}</span>
        <Money minor={quote.subtotalMinor} />
      </div>

      {quote.feeApplies && quote.zone !== null ? (
        <div className={s.totalRow} data-sf-fee-row="">
          <span className={s.totalLabel}>
            {m.deliveryFee} &middot; <TenantText>{quote.zone.name}</TenantText>
          </span>
          <Money minor={quote.feeMinor} />
        </div>
      ) : null}

      <div className={s.totalRow}>
        {/* The rate lives in the translated label, which is why quote.taxRate
            is pinned to it by test rather than interpolated here. */}
        <span className={s.totalLabel}>{m.tax}</span>
        <Money minor={quote.taxMinor} />
      </div>

      <div className={`${s.totalRow} ${s.totalFinal}`}>
        <span className={s.totalLabel}>{m.total}</span>
        <span className={`${s.ltr} ${s.totalAmount}`} dir="ltr">
          {formatMoney(quote.totalMinor)}
        </span>
      </div>
    </div>
  );
}

/**
 * The back chevron. A real link, so the destination is visible and shareable -
 * and a SOFT navigation, because a full document load would destroy the
 * in-memory checkout draft.
 *
 * NO PREFETCH, here and on every other storefront link. Next's viewport
 * prefetch asks for a per-segment RSC payload whose path it spells with dots
 * while `output: 'export'` writes that payload as nested directories, so
 * nothing serves it and every prefetch is a 404 - measured against the real
 * exported tree, and true of `/menu` just as much as of the flow. The CLICK
 * path is unaffected: it fetches a file that does exist, which is why a soft
 * navigation still preserves the draft.
 */
export function BackLink({ href, label }: { href: string; label: string }) {
  return (
    <Link className={s.back} href={href} aria-label={label} prefetch={false} data-sf-back="">
      <ChevronIcon />
    </Link>
  );
}

/**
 * The cart screen's header: back, title, and the UNIT count.
 *
 * The count is units, not lines (Storefront.dc.html:792), and an empty cart
 * still shows one - "0 items", from the same `items` string, exactly as the
 * approved empty screenshot does.
 */
export function CartHeader({
  m,
  backHref,
  count,
}: {
  m: StorefrontMessages;
  backHref: string;
  count: number;
}) {
  return (
    <header className={s.head}>
      <div className={s.headRow}>
        <BackLink href={backHref} label={m.back} />
        <h1 className={s.title}>{m.cart}</h1>
        <span className={s.count} data-sf-count="">
          {count === 1 ? m.item : fill(m.items, { n: String(count) })}
        </span>
      </div>
    </header>
  );
}

/** Details = 0, Payment = 1, Review = 2 (Storefront.dc.html:829). */
export type StepIndex = 0 | 1 | 2;

/**
 * The shared three-step chrome.
 *
 * Every segment UP TO AND INCLUDING the current one is filled; only the
 * current one glows and only its label takes the bright ink (:830). The
 * header TITLE of step 1 says "Checkout" while its progress LABEL says
 * "Details" - a deliberate asymmetry, proven in the canonical screenshots.
 */
export function StepHeader({
  m,
  title,
  backHref,
  step,
}: {
  m: StorefrontMessages;
  title: string;
  backHref: string;
  step: StepIndex;
}) {
  const labels = [m.stepDetails, m.stepPayment, m.stepReview];
  return (
    <header className={s.head}>
      <div className={`${s.headRow} ${s.headRowSteps}`}>
        <BackLink href={backHref} label={m.back} />
        <h1 className={s.title}>{title}</h1>
      </div>
      {/*
        The progress bar is a navigation landmark named by the three step
        labels. The prototype hard-codes an English `aria-label="Progress"`
        (:420); the dictionary has no key for it, so the name is composed from
        keys that DO exist rather than by inventing copy.
      */}
      <nav className={s.steps} aria-label={labels.join(' · ')} data-sf-steps={step}>
        {labels.map((label, index) => (
          <span
            className={`${s.step} ${index <= step ? s.stepFilled : ''} ${
              index === step ? s.stepNow : ''
            }`}
            key={label}
            aria-current={index === step ? 'step' : undefined}
          >
            <span className={s.stepBar} aria-hidden="true" />
            {label}
          </span>
        ))}
      </nav>
    </header>
  );
}

/**
 * The sticky footer CTA.
 *
 * NEVER the `disabled` attribute while merely blocked: a disabled control is
 * removed from the tab order, so the reason becomes unreachable by keyboard
 * and the tap that is supposed to REVEAL the error can never happen
 * (PACKET:728). `disabled` is correct in exactly one place - an in-flight
 * send, which has nowhere to move focus to.
 */
export function FooterCta({
  label,
  onActivate,
  totalMinor,
  blocked = false,
  dim = false,
  busy = false,
  live = false,
  tall = false,
  centred = false,
  leading,
  testId,
}: {
  label: ReactNode;
  onActivate: () => void;
  totalMinor?: number;
  blocked?: boolean;
  dim?: boolean;
  busy?: boolean;
  live?: boolean;
  tall?: boolean;
  centred?: boolean;
  leading?: ReactNode;
  testId: string;
}) {
  return (
    <div className={s.foot}>
      <button
        className={`${s.cta} ${tall ? s.ctaCart : ''} ${centred ? s.ctaCentre : ''} ${
          dim ? s.ctaDim : ''
        }`}
        type="button"
        onClick={busy ? undefined : onActivate}
        aria-disabled={blocked ? 'true' : undefined}
        disabled={busy}
        data-sf-cta={testId}
      >
        {live && !dim && !blocked ? <span className={s.sheen} aria-hidden="true" /> : null}
        {leading}
        <span className={s.ctaLabel}>{label}</span>
        {totalMinor === undefined ? null : (
          <span className={`${s.ctaPrice} ${s.ltr}`} dir="ltr">
            {formatMoney(totalMinor)}
          </span>
        )}
      </button>
    </div>
  );
}

/** A polite announcement region. Empty until something needs saying. */
export function Announcer({ text }: { text: string }) {
  return (
    <span className={s.srOnly} role="status" aria-live="polite" data-sf-announce="">
      {text}
    </span>
  );
}

/**
 * Interpolate a copy template, rendering named slots as NODES rather than as
 * text.
 *
 * `fill()` produces a plain string, which is right for an attribute but wrong
 * for a sentence that has to carry an item name or a money run: in an RTL
 * sentence an unisolated Latin or numeric run reorders the whole line. This
 * keeps the authored template intact and lets the caller wrap each slot -
 * `<bdi>` for a name, the `.ltr` island for money - which is the same reason
 * SearchScreen isolates `{q}`.
 *
 * An unknown placeholder is left VERBATIM, exactly as `fill()` leaves it, so a
 * missing value is visible in review instead of silently vanishing.
 */
export function Interpolate({
  template,
  values,
}: {
  template: string;
  values: Readonly<Record<string, ReactNode>>;
}) {
  const parts = template.split(/(\{\w+\})/g);
  return (
    <>
      {parts.map((part, index) => {
        const name = /^\{(\w+)\}$/.exec(part)?.[1];
        if (name !== undefined && Object.hasOwn(values, name)) {
          return <span key={`${name}-${index}`}>{values[name]}</span>;
        }
        return part;
      })}
    </>
  );
}

/** A tenant-authored or visitor-authored run, isolated inside a sentence. */
export function Bidi({ children }: { children: ReactNode }) {
  return <bdi>{children}</bdi>;
}
