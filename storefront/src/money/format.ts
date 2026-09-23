/**
 * Money formatting. Amounts are INTEGER MINOR UNITS everywhere; this is the
 * only module that produces a decimal point, and it produces a STRING — nothing
 * downstream can accidentally do arithmetic on the result.
 *
 * Design rule: `₪` is a prefix, digits are Latin in every language, and an
 * integer amount shows no decimals (`₪66`) while a non-integer shows two
 * (`₪141.60`).
 */
import type { BasisPoints, Minor } from '@/source/types';

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

/**
 * A basis-point rate as the percentage the tax label states: 1800 -> "18",
 * 1750 -> "17.5", 1725 -> "17.25". Integer arithmetic only; throws on a
 * non-integer for the same reason formatMoney does.
 */
export function formatRateBp(bp: BasisPoints): string {
  if (!Number.isInteger(bp) || bp < 0) {
    throw new TypeError(`tax rate must be integer basis points, received ${String(bp)}`);
  }
  const whole = Math.trunc(bp / 100);
  const rest = bp % 100;
  if (rest === 0) return String(whole);
  const fraction = String(rest).padStart(2, '0');
  return `${whole}.${fraction.endsWith('0') ? fraction.slice(0, 1) : fraction}`;
}
