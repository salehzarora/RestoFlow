// BIZBOT-PAYMENTS-ZCREDIT-PILOT-001E: the POS-facing answers (API_CONTRACT section 4.55.4).
// Every SQL answer is projected through a closed allowlist: adapter-only facts (the ledger row
// id, terminal / credential references, provider keys, deadlines, counters) never reach the POS,
// and an answer that does not match the closed shape fails closed (null -> 503 unavailable).
import { JsonNumber, integerText, isObject } from "./json.mjs";
import { UUID, UUID_V4 } from "./constants.mjs";
import { MAX_MINOR } from "./money.mjs";
import { RECORDING_REFUSAL_HINTS } from "./request.mjs";

export const STATES = Object.freeze(["sent", "approved", "declined", "unknown", "released"]);
export const CLASSIFICATIONS = Object.freeze(["in_progress", "freed", "provider_anomaly", "declined", "recorded",
  "orphan_approved", "approved_unrecorded", "resolved", "test_sent", "test_unknown", "test_released", "test_approved",
  "test_declined"]);
export const ANOMALY_CODES = Object.freeze(["amount_mismatch", "currency_mismatch", "preauthorization", "partial_refund",
  "refunded", "voided", "out_of_contract"]);
const REFUSAL_CODES = Object.freeze(["release_failed", ...RECORDING_REFUSAL_HINTS]);
const RESOLUTIONS = Object.freeze(["provider_voided", "provider_refunded", "test_closed"]);

// Refusal tokens the card RPCs RETURN (001D section 4.1) plus the function's own.
export const ERRORS = Object.freeze(["invalid_request", "invalid_session", "permission_denied", "conflict",
  "attempt_not_found", "precondition_failed", "card_payments_disabled", "provider_unavailable",
  "order_not_chargeable", "order_already_settled", "payment_in_progress", "amount_mismatch", "poll_limit"]);
const DETAILS = Object.freeze(["identity_in_use", "ineligible_order_state", "max_live_amount_exceeded", "no_open_shift",
  "no_active_drawer", "currency_not_supported", "max_test_amount_exceeded", "no_recording_attempt", "out_of_contract",
  "confirmation_required", "charge_may_exist", "attempt_not_freeable"]);

const TIMESTAMP = /^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|[+-]\d{2}(?::?\d{2})?)$/;
const timestamp = (value) => typeof value === "string" && TIMESTAMP.test(value);
const token = (value, set) => typeof value === "string" && set.includes(value);

/** The section 4.55.4 envelope, or null when the SQL answer is not that closed shape. */
export function projectEnvelope(value) {
  if (!isObject(value) || value.ok !== true) return null;
  const amount = integerText(value.amount_minor, 1n, MAX_MINOR);
  if (typeof value.attempt_id !== "string" || !UUID_V4.test(value.attempt_id) || !token(value.state, STATES)
    || !token(value.classification, CLASSIFICATIONS) || typeof value.recorded !== "boolean" || amount === null
    || typeof value.currency_code !== "string" || !/^[A-Z]{3}$/.test(value.currency_code)
    || !timestamp(value.server_ts)) return null;
  const out = { ok: true, attempt_id: value.attempt_id, state: value.state, classification: value.classification };
  if (value.provider_return_code !== undefined) {
    const code = integerText(value.provider_return_code, -999999, 999999);
    if (code === null) return null;
    out.provider_return_code = new JsonNumber(code);
  }
  if (value.refusal_code !== undefined) {
    if (!token(value.refusal_code, REFUSAL_CODES)) return null;
    out.refusal_code = value.refusal_code;
  }
  if (value.anomaly_code !== undefined) {
    if (!token(value.anomaly_code, ANOMALY_CODES)) return null;
    out.anomaly_code = value.anomaly_code;
  }
  if (value.resolution !== undefined) {
    if (!token(value.resolution, RESOLUTIONS)) return null;
    out.resolution = value.resolution;
  }
  out.recorded = value.recorded;
  if (value.recoverable !== undefined || value.resume_count !== undefined) {
    const count = integerText(value.resume_count, 0, 3);
    if (typeof value.recoverable !== "boolean" || count === null) return null;
    out.recoverable = value.recoverable;
    out.resume_count = new JsonNumber(count);
  }
  if (value.payment_id !== undefined) {
    if (typeof value.payment_id !== "string" || !UUID.test(value.payment_id) || value.recorded !== true) return null;
    out.payment_id = value.payment_id;
  }
  out.amount_minor = new JsonNumber(amount);
  out.currency_code = value.currency_code;
  out.server_ts = value.server_ts;
  return out;
}

/** A RETURNed refusal, or null when it is not the closed refusal shape. */
export function projectRefusal(value) {
  if (!isObject(value) || value.ok !== false || !token(value.error, ERRORS)) return null;
  const out = { ok: false, error: value.error };
  if (value.detail !== undefined) {
    if (!token(value.detail, DETAILS)) return null;
    out.detail = value.detail;
  }
  if (value.attempt_id !== undefined || value.attempt_state !== undefined) {
    if (typeof value.attempt_id !== "string" || !UUID_V4.test(value.attempt_id) || !token(value.attempt_state, STATES)) return null;
    out.attempt_id = value.attempt_id;
    out.attempt_state = value.attempt_state;
  }
  if (value.server_ts !== undefined) {
    if (!timestamp(value.server_ts)) return null;
    out.server_ts = value.server_ts;
  }
  return out;
}

/** HTTP status of a typed answer. */
export function statusOf(answer) {
  if (answer.ok) return 200;
  if (answer.error === "invalid_request") return 400;
  if (answer.error === "invalid_session") return 401;
  if (answer.error === "provider_unavailable" || answer.error === "unavailable") return 503;
  return 200;
}
