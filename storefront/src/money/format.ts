/**
 * Money formatting. Amounts are INTEGER MINOR UNITS everywhere; this is the
 * only module that produces a decimal point, and it produces a STRING — nothing
 * downstream can accidentally do arithmetic on the result.
 *
 * Design rule: `₪` is a prefix, digits are Latin in every language, and an
 * integer amount shows no decimals (`₪66`) while a non-integer shows two
 * (`₪141.60`).
 */
import type { Minor } from '@/source/types';

const SYMBOL: Readonly<Record<'ILS', string>> = { ILS: '₪' };
const MINOR_PER_MAJOR = 100;

export function isMinor(value: unknown): value is Minor {
  return typeof value === 'number' && Number.isInteger(value);
}

/**
 * Format minor units for display. Throws on a non-integer: a float here means
 * money arithmetic went wrong upstream, and rendering it would hide the bug.
 */
export function formatMoney(minor: Minor, currency: 'ILS' = 'ILS'): string {
  if (!isMinor(minor)) {
    throw new TypeError(`money must be integer minor units, received ${String(minor)}`);
  }
  const negative = minor < 0;
  const abs = Math.abs(minor);
  const major = Math.trunc(abs / MINOR_PER_MAJOR);
  const rest = abs % MINOR_PER_MAJOR;
  const digits = rest === 0 ? String(major) : `${major}.${String(rest).padStart(2, '0')}`;
  return `${negative ? '-' : ''}${SYMBOL[currency]}${digits}`;
}
