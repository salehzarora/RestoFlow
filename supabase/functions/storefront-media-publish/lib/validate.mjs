// STOREFRONT-PUBLISH-001: request validation of the storefront-media-publish
// function. Pure, dependency-free, host-agnostic (Deno edge runtime and Node).
//
// The Dashboard sends BOUNDED IDENTIFIERS ONLY (never image bytes):
//   { request_id, organization_id, restaurant_id, slot, variant,
//     source_bucket, source_key, rung }
// Every field is validated here, BEFORE any object lookup, download or engine
// work. Enumerations are checked by EXACT membership only:
//   - slot          exactly 'logo' | 'hero'                      (switch on ===)
//   - variant       exactly 'w480' | 'w960'                      (Map, recipe)
//   - source_bucket exactly 'restaurant-logos' | 'menu-images'   (Map, recipe)
// and only when the value is a primitive string, so no inherited property name
// (constructor, __proto__, prototype, toString, valueOf, ...), no case or
// whitespace variant, no empty string and no future name can pass. No ordinary
// object is ever indexed with an untrusted string.

import { sourceMaxBytes, variantWidth, RECIPE } from './recipe.mjs';

export const REQUEST_KEYS = Object.freeze([
  'request_id', 'organization_id', 'restaurant_id', 'slot', 'variant', 'source_bucket', 'source_key', 'rung',
]);
const REQUEST_KEY_SET = new Set(REQUEST_KEYS);

// Canonical lower-case UUID text (what Postgres prints and the Dashboard sends).
const UUID = '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}';
const UUID_RE = new RegExp(`^${UUID}$`);
// The private originals' key grammars (restaurant_logo_path.dart / menu_image_path.dart,
// parsed server-side by app.restaurant_logo_scope / app.menu_image_scope).
const LOGO_KEY_RE = new RegExp(`^(${UUID})/(${UUID})/logo/${UUID}\\.(?:png|jpg|jpeg|webp)$`);
const MENU_KEY_RE = new RegExp(`^(${UUID})/(${UUID})/(?:${UUID}|global)/menu_item/${UUID}/${UUID}\\.(?:png|jpg|jpeg|webp)$`);
const MAX_SOURCE_KEY_LENGTH = 512;

/**
 * The media slot a request publishes for. Exhaustive switch on exact strings:
 * owner decisions D3/D4 — logo = w480 from the receipt logo (restaurant-logos);
 * hero = w960 from the receipt logo or a menu-item original. Item images
 * (menu-images at w480) are NOT a slot of this ticket.
 */
export function slotSpec(slot) {
  if (typeof slot !== 'string') return null;
  switch (slot) {
    case 'logo': return LOGO_SLOT;
    case 'hero': return HERO_SLOT;
    default: return null;
  }
}
const LOGO_SLOT = Object.freeze({ slot: 'logo', variant: 'w480', buckets: Object.freeze(['restaurant-logos']) });
const HERO_SLOT = Object.freeze({ slot: 'hero', variant: 'w960', buckets: Object.freeze(['restaurant-logos', 'menu-images']) });

function keyMatch(bucket, key) {
  switch (bucket) {
    case 'restaurant-logos': return LOGO_KEY_RE.exec(key);
    case 'menu-images': return MENU_KEY_RE.exec(key);
    default: return null;
  }
}

const refuse = (field, reason) => ({ ok: false, field, reason });

/**
 * Review SEC-4: true when the TOP-LEVEL object of a JSON text names a key twice
 * (JSON.parse silently keeps the last one). A small depth-aware scan of the raw
 * text; only called after JSON.parse accepted it, so the text is well-formed.
 * Keys are compared after unescaping ("a" and "a" are the same key); keys of
 * nested objects are not the request's and are ignored here.
 */
export function hasDuplicateTopLevelKey(text) {
  const stack = [];
  const seen = new Set();
  let expectKey = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (c === '"') {
      let j = i + 1;
      while (j < text.length && text[j] !== '"') j += text[j] === '\\' ? 2 : 1;
      if (expectKey && stack.length === 1 && stack[0] === '{') {
        const key = JSON.parse(text.slice(i, j + 1));
        if (seen.has(key)) return true;
        seen.add(key);
        expectKey = false;
      }
      i = j;
    } else if (c === '{' || c === '[') {
      stack.push(c);
      if (stack.length === 1 && c === '{') expectKey = true;
    } else if (c === '}' || c === ']') {
      stack.pop();
    } else if (c === ',' && stack.length === 1 && stack[0] === '{') {
      expectKey = true;
    }
  }
  return false;
}

/**
 * Validates a parsed JSON request body. Returns
 *   { ok: true, value: {requestId, organizationId, restaurantId, slot, variant,
 *                       variantWidth, sourceBucket, sourceMaxBytes, sourceKey, rung} }
 * or { ok: false, field, reason } (reason: missing | unknown_field | type | value | mismatch).
 */
export function validateRequest(body) {
  if (body === null || typeof body !== 'object' || Array.isArray(body)) return refuse('body', 'type');
  // Exact key set: own enumerable keys only (JSON.parse makes "__proto__" an OWN key,
  // which is refused here like any other unknown name).
  const keys = Object.keys(body);
  for (const k of keys) {
    // Echo an unknown name only when it is a plain identifier (never reflect arbitrary text).
    if (!REQUEST_KEY_SET.has(k)) return refuse(/^[A-Za-z0-9_]{1,64}$/.test(k) ? k : '?', 'unknown_field');
  }
  for (const k of REQUEST_KEYS) if (!Object.prototype.hasOwnProperty.call(body, k)) return refuse(k, 'missing');

  const requestId = body.request_id;
  const organizationId = body.organization_id;
  const restaurantId = body.restaurant_id;
  for (const [field, v] of [['request_id', requestId], ['organization_id', organizationId], ['restaurant_id', restaurantId]]) {
    if (typeof v !== 'string') return refuse(field, 'type');
    if (!UUID_RE.test(v)) return refuse(field, 'value');
  }

  const spec = slotSpec(body.slot);
  if (spec === null) return refuse('slot', typeof body.slot === 'string' ? 'value' : 'type');

  const width = variantWidth(body.variant);
  if (width === null) return refuse('variant', typeof body.variant === 'string' ? 'value' : 'type');
  if (body.variant !== spec.variant) return refuse('variant', 'mismatch');

  const maxBytes = sourceMaxBytes(body.source_bucket);
  if (maxBytes === null) return refuse('source_bucket', typeof body.source_bucket === 'string' ? 'value' : 'type');
  if (!spec.buckets.includes(body.source_bucket)) return refuse('source_bucket', 'mismatch');

  const sourceKey = body.source_key;
  if (typeof sourceKey !== 'string') return refuse('source_key', 'type');
  if (sourceKey.length < 1 || sourceKey.length > MAX_SOURCE_KEY_LENGTH) return refuse('source_key', 'value');
  const m = keyMatch(body.source_bucket, sourceKey);
  if (m === null) return refuse('source_key', 'value');
  // The private original must live under THIS organization and restaurant
  // (the server re-proves it against storage.objects in stage).
  if (m[1] !== organizationId || m[2] !== restaurantId) return refuse('source_key', 'mismatch');

  const rung = body.rung;
  if (typeof rung !== 'number') return refuse('rung', 'type');
  if (!Number.isInteger(rung) || rung < 0 || rung >= RECIPE.ladder.length) return refuse('rung', 'value');

  return {
    ok: true,
    value: Object.freeze({
      requestId, organizationId, restaurantId,
      slot: spec.slot, variant: spec.variant, variantWidth: width,
      sourceBucket: body.source_bucket, sourceMaxBytes: maxBytes, sourceKey, rung,
    }),
  };
}
