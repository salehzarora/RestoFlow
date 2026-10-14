import type { OrderIdentity, WebOrder } from './contract';
import { validOrderNotes } from './notes';
export { validOrderNotes } from './notes';

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const UUID_V4 = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const TOKEN = /^[A-Za-z0-9_-]{42}[AEIMQUYcgkosw048]$/;
const SLUG = /^[a-z0-9]+(-[a-z0-9]+)*$/;

export class WebOrderValidationError extends Error {
  constructor() { super('invalid_request'); this.name = 'WebOrderValidationError'; }
}
export function invalid(): never { throw new WebOrderValidationError(); }

export function exactObject(value: unknown, required: readonly string[], optional: readonly string[] = []): Record<string, unknown> {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) invalid();
  const object = value as Record<string, unknown>;
  const allowed = new Set([...required, ...optional]);
  if (Object.keys(object).some((key) => !allowed.has(key)) || required.some((key) => !Object.hasOwn(object, key))) invalid();
  return object;
}
export function isCanonicalSlug(value: unknown): value is string {
  return typeof value === 'string' && value.length >= 3 && value.length <= 48 && SLUG.test(value);
}
export function isRequestId(value: unknown): value is string { return typeof value === 'string' && UUID_V4.test(value); }
export function isStatusToken(value: unknown): value is string { return typeof value === 'string' && TOKEN.test(value); }
export function validateIdentity(value: unknown): OrderIdentity {
  const object = exactObject(value, ['slug', 'request_id', 'status_token']);
  if (!isCanonicalSlug(object.slug) || !isRequestId(object.request_id) || !isStatusToken(object.status_token)) invalid();
  return { slug: object.slug, request_id: object.request_id, status_token: object.status_token };
}
function uuid(value: unknown): string {
  if (typeof value !== 'string' || !UUID.test(value)) invalid();
  return value.toLowerCase();
}
function quantity(value: unknown): number {
  if (typeof value !== 'number' || !Number.isInteger(value) || value < 1 || value > 20) invalid();
  return value;
}
export function validCustomerName(value: unknown): value is string {
  return typeof value === 'string' && [...value.trim()].length >= 1 && [...value.trim()].length <= 80 && !/[\p{Cc}\p{Cs}]/u.test(value.trim());
}
export function validCustomerPhone(value: unknown): value is string {
  return typeof value === 'string' && /^\+[1-9]\d{7,14}$/.test(value);
}
/** No pricing/tenant fields are accepted. Nothing is silently truncated or coalesced. */
export function normalizeWebOrder(value: unknown): WebOrder {
  const order = exactObject(value, ['order_type', 'customer', 'items'], ['notes']);
  if (order.order_type !== 'takeaway') invalid();
  const customer = exactObject(order.customer, ['name', 'phone']);
  if (!validCustomerName(customer.name) || !validCustomerPhone(customer.phone)) invalid();
  const notes = Object.hasOwn(order, 'notes') ? order.notes : '';
  if (!validOrderNotes(notes)) invalid();
  if (!Array.isArray(order.items) || order.items.length < 1 || order.items.length > 20) invalid();
  let units = 0;
  const items = order.items.map((value) => {
    const item = exactObject(value, ['menu_item_id', 'quantity'], ['modifiers', 'notes']);
    const menu_item_id = uuid(item.menu_item_id);
    const itemQuantity = quantity(item.quantity);
    units += itemQuantity;
    if (units > 50) invalid();
    const selected = Object.hasOwn(item, 'modifiers') ? item.modifiers : [];
    if (!Array.isArray(selected) || selected.length > 20) invalid();
    const seen = new Set<string>();
    const modifiers = selected.map((value) => {
      const modifier = exactObject(value, ['modifier_option_id', 'quantity']);
      const modifier_option_id = uuid(modifier.modifier_option_id);
      if (seen.has(modifier_option_id)) invalid();
      seen.add(modifier_option_id);
      return Object.freeze({ modifier_option_id, quantity: quantity(modifier.quantity) });
    });
    const itemNotes = Object.hasOwn(item, 'notes') ? item.notes : undefined;
    // Item notes are bounded before trim and exclude C1 controls as well as C0.
    if (itemNotes !== undefined && (!validOrderNotes(itemNotes, 140) || /[\x7f-\x9f]/u.test(itemNotes))) invalid();
    const normalizedNotes = itemNotes?.trim();
    // Omission stays omitted for backwards compatibility with note-free requests.
    return Object.freeze({ menu_item_id, quantity: itemQuantity, modifiers: Object.freeze(modifiers), ...(normalizedNotes ? { notes: normalizedNotes } : {}) });
  });
  return Object.freeze({ order_type: 'takeaway', customer: Object.freeze({ name: customer.name.trim(), phone: customer.phone }), items: Object.freeze(items), notes });
}
