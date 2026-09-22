/**
 * THE PRE-FILLED WHATSAPP MESSAGE - composed, shown, copied; never sent.
 *
 * Composed in the RESTAURANT'S content language, not the visitor's UI
 * language (CONTENT_AND_LOCALIZATION.md:268: "the owner reads it"). The
 * structure is the pack's: request code and restaurant name, one line per
 * item (`qty× name (modifiers)`), total, fulfilment, payment method, status
 * link. The Arabic wording is the prototype's own, verbatim
 * (Storefront.dc.html:768); the fixture tenant's content language is Arabic,
 * and no other content language exists in UI-001 - a second template arrives
 * with the live adapter that can say what language a tenant writes in
 * (DEFERRED WA-001).
 *
 * TWO DELIBERATE DEPARTURES FROM :768, both recorded in PHASE_EF_COMPLETION.md:
 *
 *   1. The fulfilment line for delivery names the ZONE only. The prototype
 *      appends `street, building` - dedicated CheckoutDraft fields, which the
 *      finishing authorization forbids from ever reaching message text, the
 *      copied text or a fixture result. The zone is a town chosen from a
 *      list and is already shown on every totals surface.
 *   2. The status link is the configured public origin + `/r/<ref>` (PX-2),
 *      not the literal `bizbot.app/s/MB-2487`.
 *
 * Kitchen free-text notes are never included either: they are the visitor's
 * own words and may contain anything.
 *
 * Pure. Given the same inputs it returns the same string; it reads nothing.
 */
import { formatMoney } from '@/money/format';
import type { Minor } from '@/source/types';

export type ContentLocale = 'ar';

export interface MessageLine {
  readonly qty: number;
  readonly name: string;
  /** Already joined with the approved middle-dot separator; '' when none. */
  readonly options: string;
}

export interface MessageInput {
  readonly contentLocale: ContentLocale;
  readonly displayCode: string;
  readonly restaurantName: string;
  readonly lines: readonly MessageLine[];
  readonly totalMinor: Minor;
  readonly service: 'pickup' | 'delivery';
  readonly zoneName: string | null;
  /** Absolute status URL, built by the caller from the configured origin. */
  readonly statusUrl: string;
}

/** The prototype's Arabic fragments, byte for byte (:768). */
const AR = {
  newRequest: 'طلب جديد',
  total: 'الإجمالي:',
  delivery: 'توصيل',
  pickup: 'استلام من المطعم',
  cash: 'نقداً',
  status: 'الحالة:',
  dash: ' — ',
  dot: ' · ',
} as const;

export function composeMessage(input: MessageInput): string {
  // Only one content language exists today; the switch is the seam.
  const t = AR;
  const lines = input.lines.map(
    (l) => `${l.qty}× ${l.name}${l.options === '' ? '' : ` (${l.options})`}`,
  );
  const fulfilment =
    input.service === 'delivery'
      ? `${t.delivery}${input.zoneName === null ? '' : `${t.dash}${input.zoneName}`}`
      : t.pickup;
  return [
    `${t.newRequest} ${input.displayCode}${t.dash}${input.restaurantName}`,
    ...lines,
    `${t.total} ${formatMoney(input.totalMinor)}${t.dot}${fulfilment}${t.dot}${t.cash}`,
    `${t.status} ${input.statusUrl}`,
  ].join('\n');
}
