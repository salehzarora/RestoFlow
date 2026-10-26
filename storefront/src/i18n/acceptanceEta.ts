import type { AcceptanceEta } from '../orders/contract';
import type { Locale } from './locales';
import type { OrderMessages } from './orders';

/** Always shows the stored restaurant date and zone; no client-clock countdown. */
export function acceptanceEtaCopy(eta: AcceptanceEta, locale: Locale, copy: OrderMessages) {
  const duration = new Intl.NumberFormat(locale).format(eta.preparation_minutes);
  const ready = new Intl.DateTimeFormat(locale, {
    timeZone: eta.timezone, dateStyle: 'medium', timeStyle: 'short',
  }).format(new Date(eta.ready_at));
  return Object.freeze({
    duration: copy.etaDuration.replace('{minutes}', duration),
    ready: copy.etaReadyAt.replace('{time}', ready),
    timezone: eta.timezone,
  });
}
