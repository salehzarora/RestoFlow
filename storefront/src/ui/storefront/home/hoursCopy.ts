/**
 * The ONE place the opening-hours copy is derived from the live-state model
 * (STOREFRONT-READ-001, corrected after independent review, finding B).
 *
 * The model (src/source/types.ts TenantHours) carries today's window
 * (`opens` / `closes`, empty when no window starts today), the next opening
 * instant (`nextOpen`, ISO) and its wall-clock form (`nextOpenAt`, computed on
 * the server). Every branch below renders a COMPLETE sentence: never a
 * dangling separator, dash, punctuation or empty time placeholder.
 *
 *   open   + window        -> "10:00–23:00" (numeric, LTR island)
 *   closed + window today  -> "opens {t}" (a later window today)
 *   closed + nextOpenAt    -> "opens {weekday} {t}" (the next window, on its day)
 *   closed + nothing       -> "closed for now"
 *   paused + window        -> "10:00–23:00" (paused is not closed: the window stands)
 *   paused + no window     -> "unavailable now" (paused never invents a next-open time)
 */
import { fill, type StorefrontMessages } from '@/i18n/storefront';
import type { Tenant } from '@/source/types';

export interface HoursLabel {
  readonly text: string;
  /** True for the numeric range, which is an LTR island inside RTL text. */
  readonly numeric: boolean;
}

const WEEKDAY_KEYS = ['weekday0', 'weekday1', 'weekday2', 'weekday3', 'weekday4', 'weekday5', 'weekday6'] as const;

export function weekdayName(m: StorefrontMessages, weekday: number): string {
  const key = WEEKDAY_KEYS[weekday];
  return key === undefined ? '' : m[key];
}

function hasWindow(tenant: Tenant): boolean {
  return tenant.hours.opens !== '' && tenant.hours.closes !== '';
}

/** The short hours line of the service strip, the footer and the intro. */
export function hoursLabel(tenant: Tenant, m: StorefrontMessages): HoursLabel {
  const { service, hours } = tenant;
  if (service.state === 'closed') {
    if (hasWindow(tenant)) return { text: fill(m.opensAt, { t: hours.opens }), numeric: false };
    const next = hours.nextOpenAt;
    const day = next === null ? '' : weekdayName(m, next.weekday);
    if (next !== null && day !== '' && next.time !== '') {
      return { text: fill(m.opensOn, { d: day, t: next.time }), numeric: false };
    }
    return { text: m.closedNow, numeric: false };
  }
  if (hasWindow(tenant)) return { text: `${hours.opens}–${hours.closes}`, numeric: true };
  return { text: m.unavailableNow, numeric: false };
}

/** The body of the closed notice: a full sentence in every branch. */
export function closedNoticeBody(tenant: Tenant, m: StorefrontMessages): string {
  const { hours } = tenant;
  if (hasWindow(tenant)) return fill(m.closedBody, { t: hours.opens });
  const next = hours.nextOpenAt;
  const day = next === null ? '' : weekdayName(m, next.weekday);
  if (next !== null && day !== '' && next.time !== '') return fill(m.closedBodyOn, { d: day, t: next.time });
  return m.closedBodyNoHours;
}
