/**
 * Published restaurant contact, not customer checkout input. Keep the existing
 * public_phone SQL grammar (including legacy local numbers) without guessing a
 * country, changing stored text, or accepting telephone URI parameters.
 */
const PUBLIC_PHONE = /^(?:\+[1-9][0-9]{6,14}|0[0-9]{1,2}[- ]?[0-9]{3}[- ]?[0-9]{4})$/;

export function restaurantPhoneHref(value: unknown): string | null {
  if (typeof value !== 'string' || value.length > 32 || /[^+0-9 -]/.test(value)) return null;
  if (!PUBLIC_PHONE.test(value)) return null;
  return `tel:${value.replace(/[ -]/g, '')}`;
}
