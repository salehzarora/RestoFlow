'use client';

/**
 * S9 RECEIVED - "your request was received", NOT "your order is confirmed".
 *
 * Shown once, for the request this visitor just sent (the in-memory handoff).
 * Hero on the brand surface (:516-:525), the branded summary card (:528-:531),
 * the WhatsApp CTA (:533-:536), track status (:537), the fallback block for a
 * WhatsApp that did not open (:538-:540) and the exact message preview with
 * its copy control (:541). Reveal staggered 150 -> 650ms (DESIGN_HANDOFF:138).
 *
 * THE TRUTH LINE IS NOT HIDDEN BY ANIMATION. The body that says "not
 * confirmed yet" enters with `sfUp ... both`, whose end state is fully
 * visible; under reduced motion the root rule collapses it to one frame, and
 * the browser evidence asserts it is visible after the stagger (PACKET:313).
 *
 * WHATSAPP IS OPENED, NEVER "SENT" - and in UI-001 it is not even opened: the
 * launcher is the simulated one (DEFERRED WA-001), the screen says "local
 * demo", and the continue action then shows the status view exactly as the
 * prototype's `continueWa` does (:731).
 *
 * THE COPY CONTROL copies the composed message only - the request code, the
 * restaurant's name, the lines, the total, the zone and the status link.
 * Never a name, a phone, an address or a note: none of those exist on this
 * screen. "Copied" appears only after the browser reports a successful write,
 * and for the approved 1.6 s (INTERACTIONS.md:104).
 */
import { useEffect, useRef, useState } from 'react';
import { fill, type StorefrontMessages } from '@/i18n/storefront';
import type { CopyText } from './clipboard';
import { Bidi, Interpolate } from '../checkout/flowParts';
import { TenantText } from '../TenantText';
import { DrawnCheck, LineRows, LogoDisc, WhatsAppGlyph, type RequestTenant, type ViewLine } from './requestParts';
import s from './request.module.css';

/** The approved copied-feedback duration (:733, INTERACTIONS.md:104). */
export const COPIED_MS = 1600;

export function ReceivedScreen({
  m,
  tenant,
  displayCode,
  service,
  lines,
  totalMinor,
  message,
  fallback,
  motionFull,
  copy,
  onContinue,
  onTrack,
  onWaWeb,
}: {
  m: StorefrontMessages;
  tenant: RequestTenant;
  displayCode: string;
  service: 'pickup' | 'delivery';
  lines: readonly ViewLine[];
  totalMinor: number;
  /** The composed message, in the restaurant's language. */
  message: string;
  /** Render the "WhatsApp didn't open?" block (:538). */
  fallback: boolean;
  motionFull: boolean;
  copy: CopyText;
  onContinue: () => void;
  onTrack: () => void;
  /** The fallback block's launch: the same simulated open, staying here. */
  onWaWeb: () => void;
}) {
  const [copied, setCopied] = useState(false);
  const copiedTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const alive = useRef(true);
  useEffect(() => {
    alive.current = true;
    return () => {
      alive.current = false;
      if (copiedTimer.current !== null) clearTimeout(copiedTimer.current);
    };
  }, []);

  const doCopy = async () => {
    const ok = await copy(message);
    if (!alive.current || !ok) return;
    setCopied(true);
    if (copiedTimer.current !== null) clearTimeout(copiedTimer.current);
    copiedTimer.current = setTimeout(() => {
      if (alive.current) setCopied(false);
    }, COPIED_MS);
  };

  const copyLabel = copied ? m.copied : m.copyMsg;
  const serviceTitle = service === 'delivery' ? m.delivery : fill(m.pickupAt, { r: tenant.name });

  return (
    <div className={`${s.screen} ${motionFull ? s.motionFull : ''}`} data-sf-screen="received">
      <section className={s.hero}>
        <span className={s.heroGlow} aria-hidden="true" />
        <span className={s.heroWash} aria-hidden="true" />
        <div className={s.discStage}>
          <span className={s.ring} aria-hidden="true" />
          <span className={`${s.ring} ${s.ringLate}`} aria-hidden="true" />
          <span className={s.disc} data-sf-received-disc="">
            <DrawnCheck />
          </span>
        </div>
        {/* The page's h1 (PACKET:313). */}
        <h1 className={s.heroTitle}>{m.received}</h1>
        <span className={`${s.codePill} ${s.ltr}`} dir="ltr" data-sf-request-code="">
          {displayCode}
        </span>
        <p className={s.heroBody} data-sf-received-truth="">
          <Interpolate template={m.receivedBody} values={{ r: <Bidi>{tenant.name}</Bidi> }} />
        </p>
      </section>

      <div className={s.column}>
        <div className={s.summaryCard} data-sf-request-summary="">
          <div className={s.summaryHead}>
            <LogoDisc tenant={tenant} />
            <div className={s.summaryText}>
              <div className={s.summaryName}>
                <TenantText>{tenant.name}</TenantText>
              </div>
              <div className={s.summarySub}>
                {serviceTitle} &middot; {m.cash}
              </div>
            </div>
            <span className={`${s.codeSmall} ${s.ltr}`} dir="ltr">
              {displayCode}
            </span>
          </div>
          <LineRows lines={lines} totalMinor={totalMinor} m={m} variant="received" />
        </div>

        <div className={s.ctaWrap}>
          <span className={s.halo} aria-hidden="true" />
          <button className={s.waCta} type="button" onClick={onContinue} data-sf-request-cta="continue">
            <span className={s.sheen} aria-hidden="true" />
            <WhatsAppGlyph />
            <span className={s.waLabel}>{m.continueWa}</span>
          </button>
        </div>

        <button className={s.secondary} type="button" onClick={onTrack} data-sf-request-cta="track">
          {m.trackStatus}
        </button>

        {fallback ? (
          <div className={s.fallback} data-sf-request-fallback="">
            <div className={s.fallbackTitle}>{m.waFallback}</div>
            <div className={s.fallbackRow}>
              {/* The prototype's "open WhatsApp Web" is an href="#" (:539): it
                  leaves the visitor HERE, with the copy control still in
                  reach. The same simulated launch, no navigation, no switch. */}
              <button className={s.fallbackBtn} type="button" onClick={onWaWeb} data-sf-request-cta="wa-web">
                {m.waWeb}
              </button>
              <button
                className={s.fallbackBtn}
                type="button"
                onClick={() => void doCopy()}
                aria-live="polite"
                data-sf-request-copy="fallback"
              >
                {copyLabel}
              </button>
            </div>
          </div>
        ) : null}

        <div className={s.preview} data-sf-request-preview="">
          <div className={s.previewHead}>
            <span>{m.msgPreview}</span>
            {fallback ? null : (
              <button
                className={s.copyBtn}
                type="button"
                onClick={() => void doCopy()}
                aria-live="polite"
                data-sf-request-copy="inline"
              >
                {copyLabel}
              </button>
            )}
          </div>
          <pre className={s.messageText} dir="rtl" lang="ar" data-sf-request-message="">
            {message}
          </pre>
        </div>
      </div>
    </div>
  );
}
