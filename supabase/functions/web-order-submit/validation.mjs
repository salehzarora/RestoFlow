import { RequestError } from "./errors.mjs";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const UUID_V4 = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const SLUG = /^[a-z0-9]+(-[a-z0-9]+)*$/;
// Thirty-two bytes use 43 base64url characters; the last character has two zero pad bits.
const STATUS_TOKEN = /^[A-Za-z0-9_-]{42}[AEIMQUYcgkosw048]$/;
const invalid = () => { throw new RequestError("invalid_request"); };

function exactObject(value, required, optional = []) {
  if (!value || typeof value !== "object" || Array.isArray(value)) invalid();
  const allowed = new Set([...required, ...optional]);
  if (Object.keys(value).some((key) => !allowed.has(key))) invalid();
  if (required.some((key) => !Object.hasOwn(value, key))) invalid();
}

function uuid(value, version4 = false) {
  if (typeof value !== "string" || !(version4 ? UUID_V4 : UUID).test(value)) invalid();
  return value.toLowerCase();
}

function quantity(value) {
  if (!Number.isInteger(value) || value < 1 || value > 20) invalid();
  return value;
}

function normalizeOrder(order) {
  exactObject(order, ["order_type", "customer", "items"], ["notes"]);
  if (order.order_type !== "takeaway") invalid();
  exactObject(order.customer, ["name", "phone"]);
  if (typeof order.customer.name !== "string") invalid();
  const name = order.customer.name.trim();
  if ([...name].length < 1 || [...name].length > 80 || /[\p{Cc}\p{Cs}]/u.test(name)) invalid();
  if (typeof order.customer.phone !== "string" || !/^\+[1-9]\d{7,14}$/.test(order.customer.phone)) invalid();
  const notes = Object.hasOwn(order, "notes") ? order.notes : "";
  if (typeof notes !== "string" || [...notes].length > 500 || /[\x00-\x09\x0b-\x1f\p{Cs}]/u.test(notes)) invalid();
  if (!Array.isArray(order.items) || order.items.length < 1 || order.items.length > 20) invalid();
  let totalUnits = 0;
  const items = order.items.map((item) => {
    exactObject(item, ["menu_item_id", "quantity"], ["modifiers"]);
    const menuItemId = uuid(item.menu_item_id);
    const itemQuantity = quantity(item.quantity);
    totalUnits += itemQuantity;
    if (totalUnits > 50) invalid();
    const selected = Object.hasOwn(item, "modifiers") ? item.modifiers : [];
    if (!Array.isArray(selected) || selected.length > 20) invalid();
    const optionIds = new Set();
    const modifiers = selected.map((modifier) => {
      exactObject(modifier, ["modifier_option_id", "quantity"]);
      const optionId = uuid(modifier.modifier_option_id);
      if (optionIds.has(optionId)) invalid();
      optionIds.add(optionId);
      return { modifier_option_id: optionId, quantity: quantity(modifier.quantity) };
    });
    return { menu_item_id: menuItemId, quantity: itemQuantity, modifiers };
  });
  return { order_type: "takeaway", customer: { name, phone: order.customer.phone }, items, notes };
}

/** Every object boundary is allowlisted, so prices, tenant IDs and hidden nested fields fail. */
export function validateRequest(body) {
  if (!body || typeof body !== "object" || Array.isArray(body)) invalid();
  if (body.action !== "submit" && body.action !== "status") invalid();
  const required = ["action", "slug", "request_id", "status_token"];
  if (body.action === "submit") required.push("order");
  exactObject(body, required);
  if (typeof body.slug !== "string" || body.slug.length < 3 || body.slug.length > 48 || !SLUG.test(body.slug)) invalid();
  const requestId = uuid(body.request_id, true);
  if (typeof body.status_token !== "string" || !STATUS_TOKEN.test(body.status_token)) invalid();
  const normalized = { action: body.action, slug: body.slug, request_id: requestId, status_token: body.status_token };
  if (body.action === "submit") normalized.order = normalizeOrder(body.order);
  return normalized;
}

export async function hashStatusToken(token, cryptoImpl = globalThis.crypto) {
  const digest = await cryptoImpl.subtle.digest("SHA-256", new TextEncoder().encode(token));
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
}
