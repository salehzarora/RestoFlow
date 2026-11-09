// BIZBOT-PAYMENTS-ZCREDIT-PILOT-001E: the field-specific no-card-data rule of
// app.card_safe_text_failure (DECISION D-058 point 10, closed by D-059 point 4), applied
// with the same pinned UCD 15.1.0 class tables (text_policy_tables.mjs) and the same order of
// checks: raw controls, raw allowlist and non-digit numerics, the linear 4 x max bound, NFKC
// plus the Space_Separator trim, canonical controls / allowlist / field charset, the canonical
// length range (a free-text value also needs a visible letter or digit), 12 or more digit-like
// characters raw or canonical, and the masked card pattern raw or canonical.
//
// An input that passes the raw allowlist holds only code points assigned in Unicode 15.1, whose
// NFKC mappings are stable, so the runtime's NEWER Unicode data cannot change the outcome; an older
// runtime would, so a module-load self-check of Unicode 15.0 NFKC mappings makes the policy refuse
// every value (fail closed) on such a runtime.
// Limitation (001D packet section 11 item 35, review B1): this is not an absolute masked-card
// sanitizer; the residual vectors recorded there pass this check exactly as they pass the SQL one.
import { PG_CLASSES, ZS_TRIM_CODE_POINTS } from "./text_policy_tables.mjs";

/** PostgreSQL ARE escapes (\uXXXX, \UXXXXXXXX) -> JavaScript Unicode-mode escapes. */
export function pgClassToJs(source) {
  return source.replace(/\\u([0-9A-F]{4})|\\U([0-9A-F]{8})/g, (_, short, long) => `\\u{${short ?? long}}`);
}

const re = (name, flags = "u") => new RegExp(pgClassToJs(PG_CLASSES[name]), flags);
const ALLOWED_ONLY = re("allowed_only");
const CONTROL = re("control");
const NUMERIC_OTHER = re("numeric_other");
const NOT_DIGIT = re("not_digit", "gu");
const MASK_STRIP = re("mask_strip", "gu");
const MASKED = re("masked");
const VISIBLE = re("visible");
const ZS = new Set(ZS_TRIM_CODE_POINTS);

// Unicode 15.0 compatibility mappings (Cyrillic Extended-D): absent from an older runtime's NFKC data.
export const UNICODE_15_NFKC = Object.freeze([[0x1e030, 0x0430], [0x1e043, 0x0445], [0x1e061, 0x0445], [0x1e06d, 0x04b1]]
  .map((pair) => Object.freeze(pair)));

/** True only when `normalize` (an NFKC function) maps all four Unicode 15.0 pairs. */
export function unicodeSelfCheck(normalize) {
  return UNICODE_15_NFKC.length === 4 && UNICODE_15_NFKC.every(([from, to]) =>
    normalize(String.fromCodePoint(from)) === String.fromCodePoint(to));
}

export const RUNTIME_UNICODE_OK = unicodeSelfCheck((value) => value.normalize("NFKC"));

// The field table of app.card_safe_text_failure: charset (canonical value), length range.
const FIELDS = Object.freeze({
  provider_reference: { charset: /^[A-Za-z0-9-]+$/u, min: 1, max: 32 },
  deposit_id: { charset: /^[A-Za-z0-9-]+$/u, min: 1, max: 32 },
  approval_number: { charset: /^[A-Za-z0-9]+$/u, min: 1, max: 16 },
  voucher_number: { charset: /^[A-Za-z0-9]+$/u, min: 1, max: 16 },
  card_last4: { charset: /^[0-9]+$/u, min: 4, max: 4 },
  card_brand_code: { charset: /^[A-Za-z0-9_-]+$/u, min: 1, max: 16 },
  approval_type: { charset: /^[A-Za-z0-9_-]+$/u, min: 1, max: 16 },
  pan_entry_mode: { charset: /^[A-Za-z0-9_-]+$/u, min: 1, max: 16 },
  payment_method_code: { charset: /^[A-Za-z0-9_-]+$/u, min: 1, max: 16 },
  provider_status_code: { charset: /^[A-Za-z0-9_-]+$/u, min: 1, max: 16 },
  provider_query_key: { charset: /^[a-p]+$/u, min: 1, max: 64 },
  provider_duplicate_key: { charset: /^[a-p]+$/u, min: 1, max: 64 },
  terminal_ref: { charset: /^[a-z0-9_-]+$/u, min: 1, max: 64 },
  credential_ref: { charset: /^[a-z0-9_-]+$/u, min: 1, max: 64 },
  confirmation_reference: { charset: /^[A-Za-z0-9._:/-]+$/u, min: 1, max: 64 },
  resolution_reference: { charset: /^[A-Za-z0-9._:/-]+$/u, min: 1, max: 64 },
  incident_hold_reference: { charset: /^[A-Za-z0-9._:/-]+$/u, min: 1, max: 64 },
  operator_reference: { charset: /^[A-Za-z0-9._:/-]+$/u, min: 1, max: 64 },
  actor_reference: { charset: /^[A-Za-z0-9._:/-]+$/u, min: 1, max: 64 },
  order_freed_note: { free: true, min: 1, max: 200 },
  reason: { free: true, min: 1, max: 200 },
});
for (const spec of Object.values(FIELDS)) Object.freeze(spec);

/** The field table as plain data for the parity tests: no live RegExp leaves this module. */
export const FIELD_TABLE = Object.freeze(Object.fromEntries(Object.entries(FIELDS).map(([field, spec]) => [field,
  Object.freeze({ charset: spec.charset ? spec.charset.source : null, flags: spec.charset ? spec.charset.flags : null,
    min: spec.min, max: spec.max, free: spec.free === true })])));

const codePoints = (value) => [...value].length;

/** btrim(value, the 17 Space_Separator code points). */
export function trimSpaceSeparators(value) {
  const points = [...value];
  let start = 0;
  let end = points.length;
  while (start < end && ZS.has(points[start].codePointAt(0))) start++;
  while (end > start && ZS.has(points[end - 1].codePointAt(0))) end--;
  return points.slice(start, end).join("");
}

/** app.card_text_canonical: NFKC, then the Space_Separator trim; empty = absent (null). */
export function canonicalText(value) {
  const canonical = trimSpaceSeparators(value.normalize("NFKC"));
  return canonical === "" ? null : canonical;
}

/** app.card_text_absent: null, or nothing but Space_Separator code points. */
export function textAbsent(value) {
  return value === null || value === undefined || trimSpaceSeparators(value) === "";
}

const digitCount = (value) => codePoints(value.replace(NOT_DIGIT, ""));
const masked = (value) => MASKED.test(value.replace(MASK_STRIP, ""));

/** app.card_safe_text_failure: null when the value passes, else the failed rule token. */
export function safeTextFailure(value, field) {
  if (value === null || value === undefined) return null;
  const spec = Object.hasOwn(FIELDS, field) ? FIELDS[field] : null;
  if (!spec || typeof value !== "string" || !RUNTIME_UNICODE_OK) return "charset";
  if (CONTROL.test(value)) return "control_character";
  if (!ALLOWED_ONLY.test(value) || NUMERIC_OTHER.test(value)) return "charset";
  if (codePoints(trimSpaceSeparators(value)) > 4 * spec.max) return "length";
  const canonical = canonicalText(value);
  if (canonical === null) return "length";
  if (CONTROL.test(canonical)) return "control_character";
  if (!ALLOWED_ONLY.test(canonical) || NUMERIC_OTHER.test(canonical)
    || (!spec.free && !spec.charset.test(canonical))) return "charset";
  const length = codePoints(canonical);
  if (length < spec.min || length > spec.max || (spec.free && !VISIBLE.test(canonical))) return "length";
  if (digitCount(value) >= 12 || digitCount(canonical) >= 12) return "digit_run";
  if (masked(value) || masked(canonical)) return "masked_pattern";
  return null;
}
