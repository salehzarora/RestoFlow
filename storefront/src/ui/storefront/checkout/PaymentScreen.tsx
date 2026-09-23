'use client';

/**
 * STEP 2 OF 3 - PAYMENT PRESENTATION.
 *
 * THIS STEP CAPTURES NOTHING. There is no input, no select and no textarea
 * anywhere in the approved design for it, and there is no card field of any
 * kind: the whole approved pack contains no `cvv`, `expiry`, `card number`,
 * wallet or tip. Its only outbound state is the constant `payment: 'cash'`.
 *
 * CASH IS PRE-SELECTED and states WHEN it is paid - at pickup, or to the
 * courier. CARD IS A DISABLED RADIO, visible and announced as unavailable
 * rather than hidden: "Card payment is visible and disabled, never hidden" is
 * one of the pack's own truth rules (README.md:50). It is a `div`, not a
 * button: there is nothing to press.
 */
import type { StorefrontMessages } from '@/i18n/storefront';
import type { Quote } from '@/money/quote';
import type { MotionMode } from '@/source/types';
import { CardIcon, CashIcon, CheckIcon, InfoIcon } from '../icons';
import { Banner, Bidi, FooterCta, Interpolate, Money, StepHeader } from './flowParts';
import type { FlowTenant } from './DetailsScreen';
import s from './flow.module.css';

const HEADING_ID = 'sf-pay-heading';

export function PaymentScreen({
  m,
  quote,
  tenant,
  motion,
  backHref,
  pending,
  blockedReason = null,
  onContinue,
}: {
  m: StorefrontMessages;
  quote: Quote;
  tenant: FlowTenant;
  motion: MotionMode;
  backHref: string;
  /** True while the quote for the CURRENT cart has not arrived. */
  pending: boolean;
  /** The localised reason ordering is not open (closed / paused), or null. */
  blockedReason?: string | null;
  onContinue: () => void;
}) {
  const isDelivery = quote.service === 'delivery';
  const zone = quote.zone;
  const cashDesc = isDelivery ? m.cashDelivery : m.cashPickup;

  return (
    <div className={`${s.screen} ${motion === 'calm' ? '' : s.motionFull}`} data-sf-screen="payment">
      <StepHeader m={m} title={m.payment} backHref={backHref} step={1} />

      <div className={`${s.body} ${s.bodySteps}`}>
        <section className={s.section}>
          {/* The section heading repeats the screen title, exactly as the
              approved screenshot shows; it also names the radio group. */}
          <h2 className={s.sectionTitle} id={HEADING_ID}>
            {m.payment}
          </h2>

          <div className={s.methods} role="radiogroup" aria-labelledby={HEADING_ID}>
            <button
              className={s.method}
              type="button"
              role="radio"
              aria-checked="true"
              data-sf-method="cash"
            >
              <span className={s.methodTile} aria-hidden="true">
                <CashIcon />
              </span>
              <span className={s.methodText}>
                <span className={s.methodTitleRow}>
                  <span className={s.methodName}>{m.cash}</span>
                </span>
                <span className={s.methodDesc}>{cashDesc}</span>
              </span>
              <span className={s.methodMark} aria-hidden="true">
                <CheckIcon />
              </span>
            </button>

            {/*
              A div, not a button: the design gives it no handler and no
              `disabled` attribute, because a disabled control is not announced
              at all. `aria-disabled` keeps it in the accessibility tree and
              says why.
            */}
            <div
              className={`${s.method} ${s.methodSoon}`}
              role="radio"
              aria-checked="false"
              aria-disabled="true"
              data-sf-method="card"
            >
              <span className={s.methodTile} aria-hidden="true">
                <CardIcon />
              </span>
              <span className={s.methodText}>
                <span className={s.methodTitleRow}>
                  <span className={s.methodName}>{m.card}</span>
                  <span className={s.soonPill}>{m.comingSoon}</span>
                </span>
                <span className={s.methodDesc}>{m.cardSoon}</span>
              </span>
              <span className={`${s.methodMark} ${s.methodMarkEmpty}`} aria-hidden="true" />
            </div>
          </div>
        </section>

        {/*
          The timing line, on the NEUTRAL surface rather than a tone.

          It never quotes a fee of zero: the prototype renders
          `zoneInfo{f: fmt(0)}` when no zone is known (:827), which reads as
          free delivery on the one screen that is supposed to state the price.
          With no served zone the line says only when cash is paid.
        */}
        <Banner
          tone="plain"
          alert={false}
          smallIcon
          icon={<InfoIcon />}
          title={
            isDelivery ? (
              zone === null || zone.feeMinor === null ? (
                cashDesc
              ) : (
                <>
                  {cashDesc}
                  {' — '}
                  <Interpolate
                    template={m.zoneInfo}
                    values={{
                      z: <Bidi>{zone.name}</Bidi>,
                      f: <Money minor={zone.feeMinor} />,
                      m: <Money minor={zone.minimumMinor ?? 0} />,
                    }}
                  />
                </>
              )
            ) : (
              <>
                {cashDesc}
                {' — '}
                <Bidi>{tenant.address}</Bidi>
              </>
            )
          }
          testId="cash-timing"
        />
      </div>

      {/* Payment itself is always valid - there is nothing to fill in - so
          what can block this step is a total that does not yet belong to the
          current cart, or a restaurant that is not taking orders right now. */}
      <FooterCta
        label={blockedReason ?? m.reviewCta}
        onActivate={blockedReason !== null || pending ? () => undefined : onContinue}
        totalMinor={quote.totalMinor}
        blocked={blockedReason !== null || pending}
        dim={blockedReason !== null}
        testId="to-review"
      />
    </div>
  );
}
