// BIZBOT-PAYMENTS-ZCREDIT-PILOT-001E: the exact request schemas of API_CONTRACT section 4.55.1.
// Any other shape - an unknown key, a wrong type, a non-canonical identifier or number token, a
// shift / drawer / employee / tenant / binding key - is invalid_request before any RPC call.
import { JsonNumber, integerText, isObject } from "./json.mjs";
import { minorFromToken } from "./money.mjs";
import { UUID, UUID_V4 } from "./constants.mjs";
import { safeTextFailure, textAbsent } from "./text_policy.mjs";

// The closed refusal tokens the POS may report for a recording leg (section 4.55.7).
export const RECORDING_REFUSAL_HINTS = Object.freeze(["order_not_chargeable", "conflict", "precondition_failed",
  "revoked_employee", "permission_denied", "revoked_device", "amount_mismatch", "payment_in_progress",
  "card_context_lost", "provider_recording_refused", "nonrecoverable_refusal"]);

const COMMON = ["action", "pin_session_id", "device_id", "device_session_token", "attempt_id"];

const hasExactly = (input, keys) => Object.keys(input).length === keys.length
  && keys.every((key) => Object.hasOwn(input, key));
const sessionToken = (value) => typeof value === "string" && value.length >= 1 && value.length <= 4096
  && value.trim().length > 0 && !/[\x00-\x1f\x7f]/.test(value);
// A present free-text or reference value must pass its field rule; an absent one (empty or
// Space_Separator-only) is left to the SQL body, which answers confirmation_required.
const fieldOk = (value, field) => typeof value === "string" && value.length <= 4096
  && (textAbsent(value) || safeTextFailure(value, field) === null);

/** Validate a parsed body; returns the normalized request or null (invalid_request). */
export function parseRequest(input) {
  if (!isObject(input) || typeof input.action !== "string") return null;
  const common = typeof input.pin_session_id === "string" && UUID.test(input.pin_session_id)
    && typeof input.device_id === "string" && UUID.test(input.device_id)
    && sessionToken(input.device_session_token)
    && typeof input.attempt_id === "string" && UUID_V4.test(input.attempt_id);
  if (!common) return null;
  const base = { action: input.action, pinSessionId: input.pin_session_id, deviceId: input.device_id,
    deviceSessionToken: input.device_session_token, attemptId: input.attempt_id };
  switch (input.action) {
    case "start": {
      const live = input.mode === "live";
      if (!["test", "live"].includes(input.mode)
        || !hasExactly(input, [...COMMON, "mode", "amount_minor", "currency_code",
          ...(live ? ["order_id", "expected_revision"] : [])])) return null;
      const amountMinor = minorFromToken(input.amount_minor);
      if (amountMinor === null || typeof input.currency_code !== "string" || !/^[A-Z]{3}$/.test(input.currency_code)) return null;
      if (!live) return { ...base, mode: "test", amountMinor, amountToken: input.amount_minor, currencyCode: input.currency_code,
        orderId: null, expectedRevision: null };
      const revision = integerText(input.expected_revision, 0, 2147483647);
      if (typeof input.order_id !== "string" || !UUID.test(input.order_id) || revision === null) return null;
      return { ...base, mode: "live", amountMinor, amountToken: input.amount_minor, currencyCode: input.currency_code,
        orderId: input.order_id, expectedRevision: new JsonNumber(revision) };
    }
    case "status": {
      const optional = ["source", "recording_refused", "refusal_code"].filter((key) => Object.hasOwn(input, key));
      if (!hasExactly(input, [...COMMON, ...optional])) return null;
      const source = Object.hasOwn(input, "source") ? input.source : "auto";
      if (!["auto", "operator"].includes(source)) return null;
      const refused = Object.hasOwn(input, "recording_refused") ? input.recording_refused : false;
      if (typeof refused !== "boolean") return null;
      if (refused !== Object.hasOwn(input, "refusal_code")) return null;
      if (refused && !RECORDING_REFUSAL_HINTS.includes(input.refusal_code)) return null;
      return { ...base, source, recordingRefused: refused, refusalCode: refused ? input.refusal_code : null };
    }
    case "release":
      return hasExactly(input, COMMON) ? base : null;
    case "free_order": {
      if (!hasExactly(input, [...COMMON, "reason", "confirmation_source", "confirmation_reference"])) return null;
      if (!fieldOk(input.reason, "reason") || !fieldOk(input.confirmation_reference, "confirmation_reference")
        || typeof input.confirmation_source !== "string" || !/^[a-z_]{1,32}$/.test(input.confirmation_source)) return null;
      return { ...base, reason: input.reason, confirmationSource: input.confirmation_source,
        confirmationReference: input.confirmation_reference };
    }
    default:
      return null;
  }
}
