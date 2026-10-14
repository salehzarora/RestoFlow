/** Shared note bounds without loading checkout identity or transport contracts. */
export function validOrderNotes(value: unknown, maximum = 500): value is string {
  return typeof value === 'string' && [...value].length <= maximum && !/[\x00-\x09\x0b-\x1f\p{Cs}]/u.test(value);
}
