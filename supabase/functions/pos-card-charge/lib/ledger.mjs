// BIZBOT-PAYMENTS-ZCREDIT-PILOT-001E: the private ledger module - the ONLY holder of the
// service-role credential (API_CONTRACT section 4.55.2; DEPLOYMENT section 18.3). The handler gets
// an opaque key SOURCE that only this module can unwrap, so no other module can read the key. The
// client opens only for a ProvenContext of the same request, so no service-only call can precede a
// successful context proof; the five session-proving calls append that proof's caller_auth_user_id
// as p_caller_auth_user_id themselves (DECISION D-060 point 2) - a caller cannot supply, cache or
// substitute it. card_attempt_finish takes no binding and is scope-bound to the row id and facts
// the same request's claim or adapter read returned. Each call is ONE PostgREST RPC: one
// transaction at the platform default READ COMMITTED, never a multi-call transaction. The key is
// never forwarded, returned, logged or used for the context proof.
import { isObject, stringifyJson } from "./json.mjs";
import { postJson } from "./http.mjs";
import { isProven } from "./caller.mjs";
import { platformKey } from "./config.mjs";

const SERVICE_KEY = "SUPABASE_SERVICE_ROLE_KEY";
const SOURCES = new WeakMap();

/** An opaque handle on the platform accessor that can read exactly one name: the service-role key. */
export function serviceKeySource(getEnv) {
  const source = Object.freeze({});
  SOURCES.set(source, () => getEnv(SERVICE_KEY));
  return source;
}

export class LedgerUnavailable extends Error {}

/**
 * Open the service-role client for one proven request; null when the key is missing or malformed.
 * Every method resolves the parsed JSON answer (an object) or throws LedgerUnavailable.
 */
export function openLedger({ keySource, fetchImpl, base, deadlineMs, maxBytes, proven, request }) {
  if (!isProven(proven, request)) throw new Error("ledger: no proven context for this request");
  const read = SOURCES.get(keySource);
  const key = read ? platformKey(read()) : null;
  if (!key) return null;
  const binding = proven.callerAuthUserId;
  const session = (input) => ({ p_pin_session_id: input.pinSessionId, p_device_id: input.deviceId,
    p_device_session_token: input.deviceSessionToken, p_attempt_id: input.attemptId });

  async function call(name, args) {
    const answer = await postJson(fetchImpl, `${base}/rest/v1/rpc/${name}`, {
      "Content-Type": "application/json", "Accept": "application/json", "Accept-Profile": "public",
      "Content-Profile": "public", "apikey": key, "Authorization": `Bearer ${key}`,
    }, stringifyJson(args), { deadlineMs, maxBytes });
    if (answer.kind !== "answer" || answer.status !== 200 || !isObject(answer.value)) throw new LedgerUnavailable(name);
    return answer.value;
  }

  return Object.freeze({
    claim: (input, { mode, amountToken, currencyCode, orderId, expectedRevision, maps, keyFormat }) =>
      call("card_attempt_claim", { ...session(input), p_mode: mode, p_amount_minor: amountToken,
        p_currency_code: currencyCode, p_order_id: orderId, p_expected_revision: expectedRevision,
        p_environment: maps.environment, p_terminals: maps.terminals, p_credentials: maps.credentials,
        p_key_format_version: keyFormat, p_caller_auth_user_id: binding }),
    adapterRead: (input, maps) =>
      call("card_attempt_adapter_read", { ...session(input), p_environment: maps.environment,
        p_terminals: maps.terminals, p_credentials: maps.credentials, p_caller_auth_user_id: binding }),
    markReleaseRequested: (input) =>
      call("card_attempt_mark_release_requested", { ...session(input), p_caller_auth_user_id: binding }),
    markRecordingResult: (input, refusalCode) =>
      call("card_attempt_mark_recording_result", { ...session(input), p_refusal_code: refusalCode,
        p_caller_auth_user_id: binding }),
    freeOrder: (input, { reason, confirmationSource, confirmationReference }) =>
      call("card_attempt_free_order", { ...session(input), p_reason: reason,
        p_confirmation_source: confirmationSource, p_confirmation_reference: confirmationReference,
        p_caller_auth_user_id: binding }),
    finish: (scope, { source, outcome, fields, pollSource }) =>
      call("card_attempt_finish", { p_attempt_row_id: scope.attemptRowId, p_organization_id: scope.organizationId,
        p_device_id: scope.deviceId, p_local_operation_id: scope.localOperationId, p_mode: scope.mode,
        p_amount_minor: scope.amountToken, p_currency_code: scope.currencyCode, p_source: source,
        p_outcome: outcome, p_provider_fields: fields, p_poll_source: pollSource }),
  });
}
