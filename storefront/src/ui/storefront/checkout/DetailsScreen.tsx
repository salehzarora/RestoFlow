'use client';

/**
 * STEP 1 OF 3 - DETAILS.
 *
 * Two 92px fulfilment cards, the contact pair, and - for delivery only - the
 * address block with its zone pill (DESIGN_HANDOFF.md:126).
 *
 * EVERY FIELD LIVES IN APPLICATION MEMORY. Nothing here writes to storage,
 * builds a URL, or calls anything. Validation is a pure function of the draft
 * and the Quote, so a keystroke can never become a network request carrying a
 * phone number. The form is deliberately NOT a `<form>` element: a native
 * submit would serialise every field into the address bar of a static export.
 *
 * THE CTA DIMS BUT STAYS TAPPABLE. `aria-disabled` is true from the first
 * paint; the DIM appears only after a blocked tap, and that tap scrolls to AND
 * FOCUSES the first problem. The `disabled` attribute is never used here: it
 * would remove the control from the tab order and make the reason unreachable
 * exactly for the visitors who most need it.
 *
 * EVERY VISIBLE MESSAGE IS AN EXISTING LABEL. The approved pack has no
 * "this field is required" copy, and the design reuses the label, the section
 * heading or the format mask instead. No new sentence is invented here.
 */
import { useEffect, useRef, useState, type ReactNode } from 'react';
import type { CheckoutDraft } from './CheckoutDraftProvider';
import {
  FIELD_LIMITS,
  validateCheckout,
  type CheckoutField,
  type CheckoutValidation,
} from './validation';
import { fill, type StorefrontMessages } from '@/i18n/storefront';
import type { Quote } from '@/money/quote';
import { DELIVERY_ZONES } from '@/source/zones';
import type { MotionMode } from '@/source/types';
import { CheckIcon, ChevronIcon, DeliveryIcon, PinIcon, StoreIcon } from '../icons';
import { Banner, Bidi, FooterCta, Interpolate, Money, StepHeader } from './flowParts';
import s from './flow.module.css';

/* Stable ids: one checkout per document, so there is nothing to disambiguate. */
const ID = {
  nameError: 'sf-co-name-error',
  phoneHelp: 'sf-co-phone-help',
  addrError: 'sf-co-addr-error',
  service: 'sf-co-service',
} as const;

export interface FlowTenant {
  readonly name: string;
  readonly city: string;
  readonly address: string;
  readonly opensAt: string;
  readonly pickupEnabled: boolean;
  readonly deliveryEnabled: boolean;
}

function ServiceCard({
  on,
  off,
  icon,
  name,
  desc,
  bad,
  onPick,
  testId,
}: {
  on: boolean;
  off: boolean;
  icon: ReactNode;
  name: string;
  desc: string;
  bad: boolean;
  onPick: () => void;
  testId: string;
}) {
  return (
    <button
      className={`${s.choice} ${on ? s.choiceOn : ''} ${off ? s.choiceOff : ''} ${
        bad ? s.choiceBad : ''
      }`}
      type="button"
      role="radio"
      aria-checked={on}
      /*
        A service the restaurant has switched off is announced as unavailable
        rather than removed from the tab order: `disabled` would hide the
        "unavailable now" line from exactly the visitors who cannot see it.
      */
      aria-disabled={off ? 'true' : undefined}
      onClick={off ? undefined : onPick}
      data-sf-service={testId}
    >
      <span className={s.choiceTop}>
        <span className={s.choiceIcon} aria-hidden="true">
          {icon}
        </span>
        <span className={s.choiceMark} aria-hidden="true">
          <CheckIcon />
        </span>
      </span>
      <span className={s.choiceName}>{name}</span>
      <span className={s.choiceDesc}>{desc}</span>
    </button>
  );
}

export function DetailsScreen({
  m,
  draft,
  set,
  quote,
  tenant,
  motion,
  backHref,
  pending,
  onContinue,
  onAddItems,
}: {
  m: StorefrontMessages;
  draft: CheckoutDraft;
  set: (patch: Partial<CheckoutDraft>) => void;
  quote: Quote;
  tenant: FlowTenant;
  motion: MotionMode;
  backHref: string;
  /** True while the quote for the CURRENT cart has not arrived. */
  pending: boolean;
  onContinue: () => void;
  /** "add items" leaves the step for the menu; the draft survives the move. */
  onAddItems: () => void;
}) {
  const [touched, setTouched] = useState(false);
  const [focusTick, setFocusTick] = useState(0);
  const bodyRef = useRef<HTMLDivElement>(null);

  const v: CheckoutValidation = validateCheckout(draft, quote);
  // Nothing is red before the first blocked tap, even on a wholly empty form.
  const bad = (field: CheckoutField) => touched && v.invalid.includes(field);
  const isDelivery = draft.service === 'delivery';

  useEffect(() => {
    if (focusTick === 0) return;
    // Run AFTER the render that applied aria-invalid, or the query matches
    // nothing and the tap silently does nothing at all.
    const target = bodyRef.current?.querySelector<HTMLElement>(
      '[aria-invalid="true"],[role="alert"]',
    );
    // `behavior: 'instant'` throws on pre-2023 engines, so it is not used.
    target?.scrollIntoView({ block: 'center', behavior: 'auto' });
    // FOCUS, not merely scroll: scrolling moves the viewport but leaves a
    // keyboard visitor's focus on the CTA they just pressed.
    target?.focus();
  }, [focusTick]);

  /*
   * A SERVICE THE RESTAURANT HAS SWITCHED OFF MAY NOT ARRIVE PRE-SELECTED.
   *
   * The draft starts on pickup, because it cannot know the tenant. A
   * restaurant that has turned pickup off would therefore open this step with
   * an impossible service already chosen - and validation, which only checks
   * that SOME service is set, would let it through.
   *
   * The prototype forces the switch in one direction only (:659, delivery to
   * pickup). Both directions are the same rule; modelling only one is a
   * prototype shortcut, not a design decision.
   *
   * With BOTH services off nothing is selected and nothing is changed: no
   * design exists for a restaurant that accepts neither, and inventing one
   * here would be inventing product behaviour. The CTA stays blocked.
   */
  const pickupOff = !tenant.pickupEnabled;
  const deliveryOff = !tenant.deliveryEnabled;
  useEffect(() => {
    if (draft.service === 'pickup' && pickupOff && !deliveryOff) set({ service: 'delivery' });
    else if (draft.service === 'delivery' && deliveryOff && !pickupOff) set({ service: 'pickup' });
  }, [deliveryOff, draft.service, pickupOff, set]);

  const zone = quote.zone;
  const served = zone !== null && zone.feeMinor !== null && zone.minimumMinor !== null;
  const belowMin = quote.blockers.includes('below-minimum');

  return (
    <div
      className={`${s.screen} ${motion === 'calm' ? '' : s.motionFull}`}
      data-sf-screen="checkout"
    >
      <StepHeader m={m} title={m.checkout} backHref={backHref} step={0} />

      <div className={`${s.body} ${s.bodySteps}`} ref={bodyRef}>
        {/* ------------------------------------------------ fulfilment */}
        <section className={s.section}>
          <h2 className={s.sectionTitle} id={ID.service}>
            {m.howReceive}
          </h2>
          <div className={s.choices} role="radiogroup" aria-labelledby={ID.service}>
            {/* Pickup is FIRST in the DOM, so it paints on the start side. */}
            <ServiceCard
              on={draft.service === 'pickup'}
              off={pickupOff}
              icon={<StoreIcon />}
              name={m.pickup}
              desc={
                tenant.pickupEnabled ? fill(m.pickupDesc, { a: tenant.city }) : m.unavailableNow
              }
              bad={bad('service')}
              onPick={() => set({ service: 'pickup' })}
              testId="pickup"
            />
            <ServiceCard
              on={draft.service === 'delivery'}
              off={deliveryOff}
              icon={<DeliveryIcon />}
              name={m.delivery}
              desc={tenant.deliveryEnabled ? m.deliveryDesc : m.unavailableNow}
              bad={bad('service')}
              onPick={() => set({ service: 'delivery' })}
              testId="delivery"
            />
          </div>
          {bad('service') ? (
            <div className={s.fieldError} role="alert" tabIndex={-1}>
              {m.howReceive}
            </div>
          ) : null}
        </section>

        {/* ---------------------------------------------------- contact */}
        <section className={s.section}>
          <h2 className={s.sectionTitle}>{m.yourDetails}</h2>

          <label className={s.field}>
            <span className={s.label}>{m.fullName}</span>
            <input
              className={`${s.input} ${bad('fullName') ? s.inputBad : ''}`}
              value={draft.fullName}
              onChange={(e) => set({ fullName: e.target.value.slice(0, FIELD_LIMITS.fullName) })}
              autoComplete="name"
              aria-invalid={bad('fullName') ? 'true' : undefined}
              aria-describedby={bad('fullName') ? ID.nameError : undefined}
              data-sf-field="fullName"
            />
          </label>
          {bad('fullName') ? (
            <span className={s.fieldError} role="alert" id={ID.nameError}>
              {/* The design's own message for an empty name is the LABEL. */}
              {m.fullName}
            </span>
          ) : null}

          <label className={s.field}>
            <span className={s.label}>{m.phone}</span>
            <input
              className={`${s.input} ${s.phone} ${bad('phone') ? s.inputBad : ''}`}
              value={draft.phone}
              onChange={(e) => set({ phone: e.target.value.slice(0, FIELD_LIMITS.phone) })}
              dir="ltr"
              /* inputmode, NOT type="tel": the pack specifies the keypad hint
                 and nothing else (CONTENT_AND_LOCALIZATION.md:225). */
              inputMode="tel"
              autoComplete="tel"
              placeholder={m.phoneHint}
              aria-invalid={bad('phone') ? 'true' : undefined}
              aria-describedby={ID.phoneHelp}
              data-sf-field="phone"
            />
          </label>
          {/* The helper SWAPS to the format mask and turns danger; it is not an
              alert, because the placeholder it mirrors never was. */}
          <span
            className={`${s.help} ${bad('phone') ? s.helpBad : ''}`}
            id={ID.phoneHelp}
            data-sf-phone-help=""
          >
            {bad('phone') ? m.phoneHint : m.phoneHelp}
          </span>
        </section>

        {/* --------------------------------------------------- delivery */}
        {isDelivery ? (
          <section className={s.section} data-sf-address="">
            <h2 className={s.sectionTitle}>{m.address}</h2>

            <label className={s.field}>
              <span className={s.label}>{m.city}</span>
              <span className={s.selectWrap}>
                <select
                  className={`${s.select} ${bad('zoneId') ? s.inputBad : ''}`}
                  value={draft.zoneId}
                  onChange={(e) => set({ zoneId: e.target.value })}
                  aria-invalid={bad('zoneId') ? 'true' : undefined}
                  data-sf-field="zoneId"
                >
                  <option value="">{m.chooseCity}</option>
                  {/*
                    NO dir="auto" here. An <option> is a structural block, and
                    `dir="auto"` on one resolves its own alignment from the
                    first strong character - so one Arabic town in an English
                    list would jump to the opposite edge from its neighbours.
                    The list keeps the page direction; a <select> gives no
                    inner run to isolate.
                  */}
                  {DELIVERY_ZONES.map((z) => (
                    <option key={z.id} value={z.id}>
                      {z.name}
                    </option>
                  ))}
                </select>
                <svg className={s.selectChevron} viewBox="0 0 24 24" aria-hidden="true">
                  <path d="M6 9l6 6 6-6" />
                </svg>
              </span>
            </label>

            {/* The zone pill: info when served, danger out of zone, warning
                below the minimum. One action at most, and never a "0" fee. */}
            {zone === null ? null : !served ? (
              <Banner
                tone="bad"
                smallIcon
                icon={<PinIcon />}
                title={
                  <Interpolate template={m.outsideZone} values={{ z: <Bidi>{zone.name}</Bidi> }} />
                }
                body={m.outsideZoneBody}
                /* A-4: with pickup switched off this recovery would be a dead
                   end, so it is withheld rather than offered and refused. */
                action={
                  tenant.pickupEnabled
                    ? { label: m.switchPickup, onAction: () => set({ service: 'pickup' }) }
                    : undefined
                }
                testId="outside-zone"
              />
            ) : belowMin ? (
              <Banner
                tone="warn"
                smallIcon
                icon={<PinIcon />}
                title={
                  <Interpolate
                    template={m.belowMin}
                    values={{
                      z: <Bidi>{zone.name}</Bidi>,
                      m: <Money minor={zone.minimumMinor ?? 0} />,
                    }}
                  />
                }
                body={
                  <Interpolate
                    template={m.belowMinBody}
                    values={{ d: <Money minor={quote.shortfallMinor} /> }}
                  />
                }
                action={{ label: m.addItems, onAction: onAddItems }}
                testId="below-minimum"
              />
            ) : (
              <Banner
                tone="acc"
                smallIcon
                alert={false}
                icon={<PinIcon />}
                title={
                  <Interpolate
                    template={m.zoneInfo}
                    values={{
                      z: <Bidi>{zone.name}</Bidi>,
                      f: <Money minor={zone.feeMinor ?? 0} />,
                      m: <Money minor={zone.minimumMinor ?? 0} />,
                    }}
                  />
                }
                testId="zone-info"
              />
            )}

            <label className={s.field}>
              <span className={s.label}>{m.area}</span>
              <input
                className={s.input}
                value={draft.area}
                onChange={(e) => set({ area: e.target.value.slice(0, FIELD_LIMITS.area) })}
                data-sf-field="area"
              />
            </label>

            <div className={s.pair}>
              <label className={s.field}>
                <span className={s.label}>{m.street}</span>
                <input
                  className={`${s.input} ${bad('street') ? s.inputBad : ''}`}
                  value={draft.street}
                  onChange={(e) => set({ street: e.target.value.slice(0, FIELD_LIMITS.street) })}
                  aria-invalid={bad('street') ? 'true' : undefined}
                  aria-describedby={bad('street') || bad('building') ? ID.addrError : undefined}
                  data-sf-field="street"
                />
              </label>
              <label className={s.field}>
                <span className={s.label}>{m.building}</span>
                <input
                  className={`${s.input} ${bad('building') ? s.inputBad : ''}`}
                  value={draft.building}
                  onChange={(e) =>
                    set({ building: e.target.value.slice(0, FIELD_LIMITS.building) })
                  }
                  aria-invalid={bad('building') ? 'true' : undefined}
                  aria-describedby={bad('street') || bad('building') ? ID.addrError : undefined}
                  data-sf-field="building"
                />
              </label>
            </div>
            {bad('street') || bad('building') ? (
              <span className={s.fieldError} role="alert" id={ID.addrError}>
                {/* ONE shared message for the pair, as designed. */}
                {`${m.street} · ${m.building}`}
              </span>
            ) : null}

            <label className={s.field}>
              <span className={s.label}>{m.apt}</span>
              <input
                className={s.input}
                value={draft.apartment}
                onChange={(e) =>
                  set({ apartment: e.target.value.slice(0, FIELD_LIMITS.apartment) })
                }
                data-sf-field="apartment"
              />
            </label>

            <label className={s.field}>
              <span className={s.label}>{m.deliveryNotes}</span>
              <textarea
                className={s.textarea}
                rows={2}
                value={draft.deliveryNotes}
                onChange={(e) =>
                  set({ deliveryNotes: e.target.value.slice(0, FIELD_LIMITS.deliveryNotes) })
                }
                data-sf-field="deliveryNotes"
              />
            </label>
          </section>
        ) : null}
      </div>

      <FooterCta
        label={
          <>
            {m.stepPayment}
            <ChevronIcon />
          </>
        }
        onActivate={() => {
          // A stale total may be SHOWN, but nothing may be ordered against it.
          if (pending) return;
          if (v.ok) {
            onContinue();
            return;
          }
          setTouched(true);
          setFocusTick((n) => n + 1);
        }}
        totalMinor={quote.totalMinor}
        blocked={!v.ok || pending}
        dim={touched && !v.ok}
        testId="to-payment"
      />
    </div>
  );
}
