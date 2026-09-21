/**
 * CART PERSISTENCE — the ONE module in the storefront permitted to touch
 * localStorage, and the only key it may touch.
 *
 * SCOPE, deliberately closed:
 *   - exactly one key per tenant: `sf:v1:cart:<slug>`
 *   - the value is a CartState and nothing else
 *   - no generic get/set, so nothing else can be smuggled through
 *
 * WHAT MAY NEVER BE STORED HERE: customer names, phone numbers or addresses, a
 * checkout draft, delivery zones, request references or status, payment data,
 * tokens or secrets, and analytics of any kind. The persisted shape carries
 * IDS AND PRIMITIVES ONLY - never a resolved name, price or image, because
 * those come from the menu and must never be trusted from storage.
 *
 * READ SIDE: treat every byte as HOSTILE INPUT. A visitor can edit
 * localStorage freely, and so can any script that ever runs on this origin, so
 * the parser validates structurally and semantically and returns an EMPTY cart
 * on the first thing it does not like. It never throws at the call site, never
 * repairs a partial payload into something plausible, and never renders stored
 * text as HTML.
 */
import { isValidSlug, sanitizeText } from '@/theme/sanitize';
import { MAX_NOTE, MAX_QTY, MIN_QTY } from '@/money/pricing';
import type { CartLine, CartState } from '@/source/types';

const NAMESPACE = 'sf:v1:cart:';

/** Refuse anything larger than this before parsing. Measured in UTF-8 BYTES. */
const MAX_BYTES = 64 * 1024;

/**
 * The payload's size in UTF-8 BYTES.
 *
 * `String.prototype.length` counts UTF-16 code units, which is NOT the stored
 * size: one Arabic or Hebrew character is a single code unit but two UTF-8
 * bytes, and most emoji are two code units but four bytes. Measuring by length
 * therefore admitted payloads far over the documented 64 KiB ceiling.
 *
 * `TextEncoder` is a browser global (and standard in Node), so this stays a
 * client-safe module with no Node-only API. It is constructed lazily and reused
 * because a stored cart is read on every page load.
 */
let encoder: TextEncoder | null = null;
function utf8Bytes(text: string): number {
  if (encoder === null) encoder = new TextEncoder();
  return encoder.encode(text).length;
}
/** Bounds so a crafted payload cannot exhaust memory or the render tree. */
export const MAX_LINES = 50;
const MAX_GROUPS_PER_LINE = 12;
const MAX_OPTIONS_PER_GROUP = 12;
const MAX_ID_LENGTH = 64;
const MAX_MENU_VERSION = 64;

/** Ids we mint and accept: short, lowercase-ish, no separators or traversal. */
const SAFE_ID = /^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$/;
/** Keys that must never be accepted as an object key. */
const FORBIDDEN_KEYS = new Set(['__proto__', 'prototype', 'constructor']);

function isSafeId(value: unknown): value is string {
  return typeof value === 'string' && value.length <= MAX_ID_LENGTH && SAFE_ID.test(value);
}

/** Own, enumerable, non-forbidden keys only. */
/**
 * True when the object carries an OWN property whose key is one a prototype
 * chain reserves. `JSON.parse` creates these as real own properties - unlike an
 * object LITERAL, where `__proto__:` is a prototype assignment and no own key
 * exists at all - so this is reachable only from parsed input, which is exactly
 * the untrusted path.
 */
function hasForbiddenKey(value: object): boolean {
  return Object.keys(value).some((key) => FORBIDDEN_KEYS.has(key));
}

function safeEntries(value: object): Array<[string, unknown]> {
  const out: Array<[string, unknown]> = [];
  for (const key of Object.getOwnPropertyNames(value)) {
    if (FORBIDDEN_KEYS.has(key)) continue;
    out.push([key, (value as Record<string, unknown>)[key]]);
  }
  return out;
}

function isPlainObject(value: unknown): value is Record<string, unknown> {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) return false;
  const proto = Object.getPrototypeOf(value);
  return proto === Object.prototype || proto === null;
}

export function cartKey(slug: string): string | null {
  if (!isValidSlug(slug)) return null;
  return `${NAMESPACE}${slug}`;
}

/**
 * The store, or null when unavailable. The property ACCESS is inside the try on
 * purpose: reading the global throws, rather than returning undefined, when
 * site data is blocked.
 */
function store(): Storage | null {
  try {
    const found = (globalThis as { localStorage?: Storage }).localStorage;
    return found ?? null;
  } catch {
    return null;
  }
}

export function emptyCart(slug: string, menuVersion: string): CartState {
  return { schema: 1, slug, menuVersion, lines: [] };
}

/** Validate one line. Returns null if anything at all is wrong. */
function parseLine(raw: unknown): CartLine | null {
  if (!isPlainObject(raw)) return null;

  if (hasForbiddenKey(raw)) return null;

  const { lineId, itemId, qty, selections, note } = raw as Record<string, unknown>;
  if (!isSafeId(lineId) || !isSafeId(itemId)) return null;
  if (typeof qty !== 'number' || !Number.isInteger(qty) || qty < MIN_QTY || qty > MAX_QTY) {
    return null;
  }
  if (note !== undefined && typeof note !== 'string') return null;
  if (typeof note === 'string' && note.length > MAX_NOTE * 4) return null;

  if (!isPlainObject(selections)) return null;
  // A forbidden own key REJECTS the line. Dropping it and keeping the rest
  // would hand back a partly-trusted cart - the very thing this module refuses
  // - and would under-price it without telling the visitor.
  if (hasForbiddenKey(selections)) return null;
  const groupEntries = safeEntries(selections);
  if (groupEntries.length > MAX_GROUPS_PER_LINE) return null;

  const cleanSelections: Record<string, readonly string[]> = Object.create(null) as Record<
    string,
    readonly string[]
  >;
  for (const [groupId, optionIds] of groupEntries) {
    if (!isSafeId(groupId)) return null;
    if (!Array.isArray(optionIds)) return null;
    if (optionIds.length > MAX_OPTIONS_PER_GROUP) return null;
    const ids: string[] = [];
    for (const optionId of optionIds) {
      if (!isSafeId(optionId)) return null;
      if (ids.includes(optionId)) return null; // no duplicates
      ids.push(optionId);
    }
    cleanSelections[groupId] = ids;
  }

  return {
    lineId,
    itemId,
    qty,
    selections: { ...cleanSelections },
    // Sanitised, never rendered as HTML anywhere.
    note: sanitizeText(typeof note === 'string' ? note : '', MAX_NOTE),
  };
}

/**
 * Parse a stored payload. `slug` and `menuVersion` are what the CURRENT page
 * expects; a cart stored for another tenant or another menu is discarded rather
 * than shown, because its item and option ids may mean something else now.
 */
export function parseCart(rawText: unknown, slug: string, menuVersion: string): CartState {
  const empty = emptyCart(slug, menuVersion);
  if (typeof rawText !== 'string' || rawText.length === 0) return empty;
  if (utf8Bytes(rawText) > MAX_BYTES) return empty;

  let parsed: unknown;
  try {
    parsed = JSON.parse(rawText);
  } catch {
    return empty;
  }
  if (!isPlainObject(parsed)) return empty;

  if (hasForbiddenKey(parsed)) return empty;

  const { schema, slug: storedSlug, menuVersion: storedVersion, lines } = parsed as Record<
    string,
    unknown
  >;
  if (schema !== 1) return empty;
  if (typeof storedSlug !== 'string' || storedSlug !== slug || !isValidSlug(storedSlug)) {
    return empty;
  }
  if (
    typeof storedVersion !== 'string' ||
    storedVersion.length === 0 ||
    storedVersion.length > MAX_MENU_VERSION ||
    storedVersion !== menuVersion
  ) {
    return empty;
  }
  if (!Array.isArray(lines) || lines.length > MAX_LINES) return empty;

  const clean: CartLine[] = [];
  const seenLineIds = new Set<string>();
  for (const raw of lines) {
    const line = parseLine(raw);
    // One bad line invalidates the payload: a partially-trusted cart is worse
    // than an empty one, because the visitor cannot tell what was dropped.
    if (line === null) return empty;
    if (seenLineIds.has(line.lineId)) return empty;
    seenLineIds.add(line.lineId);
    clean.push(line);
  }

  return { schema: 1, slug, menuVersion, lines: clean };
}

/** Read the cart for this tenant. Any problem yields an empty cart. */
export function loadCart(slug: string, menuVersion: string): CartState {
  const key = cartKey(slug);
  if (key === null) return emptyCart(slug, menuVersion);
  const found = store();
  if (found === null) return emptyCart(slug, menuVersion);
  try {
    return parseCart(found.getItem(key), slug, menuVersion);
  } catch {
    return emptyCart(slug, menuVersion);
  }
}

/** Serialise exactly the CartState shape - never a wider object. */
export function serialiseCart(state: CartState): string {
  return JSON.stringify({
    schema: 1,
    slug: state.slug,
    menuVersion: state.menuVersion,
    lines: state.lines.map((l) => ({
      lineId: l.lineId,
      itemId: l.itemId,
      qty: l.qty,
      selections: l.selections,
      note: l.note,
    })),
  });
}

/** Persist. Refuses to write anything that would not survive its own parser. */
export function saveCart(state: CartState): void {
  const key = cartKey(state.slug);
  if (key === null) return;
  const found = store();
  if (found === null) return;
  const text = serialiseCart(state);
  if (utf8Bytes(text) > MAX_BYTES) return;
  // Round-trip guard: if what we are about to write would be rejected on read,
  // do not write it at all.
  if (parseCart(text, state.slug, state.menuVersion).lines.length !== state.lines.length) return;
  try {
    if (state.lines.length === 0) found.removeItem(key);
    else found.setItem(key, text);
  } catch {
    /* Quota or refused writes. The cart simply does not persist. */
  }
}
