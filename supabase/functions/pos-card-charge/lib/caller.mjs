// BIZBOT-PAYMENTS-ZCREDIT-PILOT-001E: the CALLER-SCOPED client (API_CONTRACT section 4.55.2).
// It carries the caller's own Authorization header unchanged plus the public anon key and calls
// exactly one RPC, the read-only context proof public.card_attempt_context. PostgREST verifies
// the JWT; the function never decodes it (decoding is not authentication). A successful proof
// becomes a request-local ProvenContext - the only source of the original-caller binding
// (caller_auth_user_id, DECISION D-060 point 2) that the same request's service calls carry.
import { isObject, stringifyJson } from "./json.mjs";
import { postJson } from "./http.mjs";
import { ROLES, UUID } from "./constants.mjs";

const PROVEN = new WeakSet();

/** A proof is usable only by the request that produced it. */
export function isProven(value, request) {
  return PROVEN.has(value) && value.request === request;
}

const PROOF_REFUSALS = new Set(["invalid_session", "permission_denied", "invalid_request", "conflict"]);

/**
 * Resolves one of:
 *   { kind: 'proven', proven }            - ok:true, shape-checked, bound to `request`
 *   { kind: 'refused', error }            - a RETURNed proof refusal (no write anywhere)
 *   { kind: 'unavailable' }               - no usable answer
 * An upstream 401 / 403 (JWT refused by PostgREST) is the refusal invalid_session.
 */
export async function proveContext({ request, base, anonKey, authorization, fetchImpl, deadlineMs, maxBytes, args }) {
  const answer = await postJson(fetchImpl, `${base}/rest/v1/rpc/card_attempt_context`, {
    "Content-Type": "application/json", "Accept": "application/json", "Accept-Profile": "public",
    "Content-Profile": "public", "apikey": anonKey, "Authorization": authorization,
  }, stringifyJson({ p_pin_session_id: args.pinSessionId, p_device_id: args.deviceId,
    p_device_session_token: args.deviceSessionToken, p_order_id: args.orderId, p_attempt_id: args.attemptId }),
  { deadlineMs, maxBytes });
  if (answer.kind !== "answer") return { kind: "unavailable" };
  if (answer.status === 401 || answer.status === 403) return { kind: "refused", error: "invalid_session" };
  const value = answer.value;
  if (answer.status !== 200 || !isObject(value)) return { kind: "unavailable" };
  if (value.ok === false) {
    return PROOF_REFUSALS.has(value.error) ? { kind: "refused", error: value.error } : { kind: "unavailable" };
  }
  const ids = ["caller_auth_user_id", "organization_id", "restaurant_id", "branch_id", "device_id",
    "employee_profile_id", "membership_id"];
  if (value.ok !== true || !ids.every((key) => typeof value[key] === "string" && UUID.test(value[key]))
    || value.device_id !== args.deviceId || !ROLES.includes(value.role) || typeof value.server_ts !== "string"
    || (value.attempt !== null && value.attempt !== undefined && !isObject(value.attempt))) return { kind: "unavailable" };
  const proven = Object.freeze({
    request,
    callerAuthUserId: value.caller_auth_user_id,
    organizationId: value.organization_id,
    restaurantId: value.restaurant_id,
    branchId: value.branch_id,
    deviceId: value.device_id,
    role: value.role,
    employeeProfileId: value.employee_profile_id,
    membershipId: value.membership_id,
    attempt: value.attempt ?? null,
    serverTs: value.server_ts,
  });
  PROVEN.add(proven);
  return { kind: "proven", proven };
}
