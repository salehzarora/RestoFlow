'use client';

/**
 * Pieces shared by the received and status views: the tenant scalars the
 * route hands the runtime, the logo disc, the WhatsApp glyph, and the
 * local-demo disclosure.
 */
import { CheckIcon } from '../icons';
import { formatMoney } from '@/money/format';
import type { StorefrontMessages } from '@/i18n/storefront';
import type { Minor } from '@/source/types';
import { TenantText } from '../TenantText';
import s from './request.module.css';

/** What a request route passes down: scalars, never the menu or a dictionary. */
export interface RequestTenant {
  readonly name: string;
  readonly logo: string | null;
}

export function LogoDisc({ tenant, small = false }: { tenant: RequestTenant; small?: boolean }) {
  return (
    <span className={small ? s.headLogo : s.logo} aria-hidden="true">
      <span className={s.logoInner}>
        {tenant.logo === null ? (
          <span className={s.logoInitial}>{tenant.name.trim().slice(0, 1)}</span>
        ) : (
          /* eslint-disable-next-line @next/next/no-img-element */
          <img src={tenant.logo} alt="" width={40} height={40} decoding="async" />
        )}
      </span>
    </span>
  );
}

/** The WhatsApp mark (:535). Filled, never mirrored (CONTENT:219). */
export function WhatsAppGlyph() {
  return (
    <svg className={s.waGlyph} viewBox="0 0 24 24" aria-hidden="true" focusable="false">
      <path d="M12 2a10 10 0 00-8.6 15.1L2 22l5-1.3A10 10 0 1012 2zm0 1.8a8.2 8.2 0 11-4.2 15.3l-.3-.2-3 .8.8-2.9-.2-.3A8.2 8.2 0 0112 3.8zM8.9 7.2c-.2 0-.5 0-.7.3-.3.3-1 1-1 2.4s1 2.8 1.2 3c.1.2 2 3.2 5 4.4 2.5 1 3 .8 3.5.7.5 0 1.7-.7 1.9-1.4.2-.7.2-1.2.2-1.4-.1-.1-.3-.2-.5-.3l-1.9-.9c-.3-.1-.5-.2-.6.1l-.8 1c-.2.2-.3.2-.6.1-.3-.2-1.2-.5-2.3-1.5-.9-.8-1.5-1.7-1.6-2-.2-.3 0-.4.1-.6l.5-.6c.2-.2.2-.4.3-.6l.1-.3-.9-2c-.2-.5-.4-.4-.6-.4h-.5z" />
    </svg>
  );
}

export function DrawnCheck() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true" focusable="false">
      <path d="M5 12l5 5L20 7" />
    </svg>
  );
}

export { CheckIcon };

/** One resolved line of the request, as both views render it (:530, :571). */
export interface ViewLine {
  readonly key: string;
  readonly qty: number;
  readonly name: string;
  readonly options: string;
  readonly totalMinor: Minor;
}

export function LineRows({
  lines,
  totalMinor,
  m,
  variant,
}: {
  lines: readonly ViewLine[];
  totalMinor: Minor;
  m: StorefrontMessages;
  variant: 'received' | 'status';
}) {
  const status = variant === 'status';
  return (
    <div className={`${s.lines} ${status ? s.linesStatus : ''}`} data-sf-request-lines={variant}>
      {lines.map((line) => (
        <div className={s.lineRow} key={line.key} data-sf-request-line="">
          <span className={s.lineText}>
            <span className={`${s.lineQty} ${s.ltr}`} dir="ltr">
              {`${line.qty}×`}
            </span>{' '}
            <TenantText>{line.name}</TenantText>
          </span>
          <span className={`${s.lineTotal} ${s.ltr}`} dir="ltr">
            {formatMoney(line.totalMinor)}
          </span>
        </div>
      ))}
      <div className={s.totalRow}>
        <span>{status ? `${m.total} · ${m.cash}` : m.total}</span>
        <span className={`${s.ltr} ${status ? '' : s.totalAccent}`} dir="ltr">
          {formatMoney(totalMinor)}
        </span>
      </div>
    </div>
  );
}

/**
 * The local-demo disclosure. An execution clarification (FINISH 4.4), not
 * original copy: the storefront has no demo-mode notice of its own, and a
 * received screen that opened no WhatsApp must say so somewhere the visitor
 * can read.
 */
export function DemoNote({ m }: { m: StorefrontMessages }) {
  return (
    <p className={s.demoNote} role="note" data-sf-demo-note="">
      {m.demoNotice}
    </p>
  );
}
