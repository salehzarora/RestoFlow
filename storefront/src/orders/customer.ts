/** Customer field checks without loading checkout identity or payload parsing. */
export function validCustomerName(value: unknown): value is string {
  return typeof value === 'string' && [...value.trim()].length >= 1 && [...value.trim()].length <= 80 && !/[\p{Cc}\p{Cs}]/u.test(value.trim());
}
export function validCustomerPhone(value: unknown): value is string {
  return typeof value === 'string' && /^\+[1-9]\d{7,14}$/.test(value);
}
