/** Customer field checks without loading checkout identity or payload parsing. */
export function validCustomerName(value: unknown): value is string {
  return typeof value === 'string' && [...value.trim()].length >= 1 && [...value.trim()].length <= 80 && !/[\p{Cc}\p{Cs}]/u.test(value.trim());
}
export function validCustomerPhone(value: unknown): value is string {
  return typeof value === 'string' && /^\+[1-9]\d{7,14}$/.test(value);
}

// Israeli mobile, geographic landline and national landline/VoIP shapes.
// Format validation does not assert that a subscriber number is allocated.
const ISRAELI_LOCAL_PHONE = /^(?:05\d{8}|0[23489][2-9]\d{6}|07[2-9][2-9]\d{6})$/;

/** Checkout input only. The API validator above remains strictly E.164. */
export function normalizeCheckoutPhone(value: unknown): string | null {
  if (typeof value !== 'string') return null;
  // Only ordinary spaces are padding; controls and other punctuation are errors.
  const input = value.replace(/^ +| +$/g, '');
  if (input.startsWith('+')) {
    // Preserve the existing international contract, independently of local shapes.
    return validCustomerPhone(input) ? input : null;
  }
  if (!/^\d+(?:[ -]\d+)*$/.test(input)) return null;
  const local = input.replace(/[ -]/g, '');
  return ISRAELI_LOCAL_PHONE.test(local) ? `+972${local.slice(1)}` : null;
}
