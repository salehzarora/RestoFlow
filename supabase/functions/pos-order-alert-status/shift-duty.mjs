import { configuration, hash, object, readJson, response, rpc, timestamp, UUID } from "../_shared/pos-order-alert.mjs";

const uuid = value => typeof value === "string" && UUID.test(value);
const rpcNames = {
  status: "pos_shift_order_alert_status",
  "token/refresh": "pos_refresh_shift_order_alert_token",
  revoke: "pos_revoke_shift_order_alert",
};

// These native routes can use or invalidate one existing consent. Enrollment
// belongs to the separate foreground PIN-authenticated RPCs.
export async function handleDutyRequest(request, route, getEnv, fetchImpl, cryptoImpl, timeoutMs) {
  const revoke = route === "revoke";
  const refresh = route === "token/refresh";
  if (!revoke && getEnv("POS_ORDER_ALERTS_ENABLED") !== "true") return response({ ok: false, error: "disabled" }, 503);
  const bearer = /^Bearer ([0-9a-f]{64})$/.exec(request.headers.get("authorization") ?? "");
  if (!bearer) return response({ ok: false, error: "unauthorized" }, 401);
  const input = await readJson(request, refresh ? 6144 : 2048);
  if (!object(input) || Object.keys(input).length !== (refresh ? 4 : 2)
    || !uuid(input.installation_id) || !uuid(input.consent_id)
    || (refresh && (!uuid(input.generation) || typeof input.fcm_token !== "string"
      || !/^[^\s\x00-\x1f\x7f]{20,4096}$/.test(input.fcm_token)))) {
    return response({ ok: false, error: "invalid_request" }, 400);
  }
  const config = configuration(getEnv);
  if (!config) return response({ ok: false, error: "unavailable" }, 503);
  const args = { p_installation_id: input.installation_id, p_consent_id: input.consent_id,
    [revoke ? "p_revoke_hash" : "p_status_secret_hash"]: await hash(bearer[1], cryptoImpl) };
  if (refresh) {
    args.p_fcm_token = input.fcm_token;
    args.p_expected_generation = input.generation;
  }
  const result = await rpc(rpcNames[route], args, config, fetchImpl, timeoutMs);
  if (object(result) && result.ok === false && result.error === "unauthorized") return response({ ok: false, error: "unauthorized" }, 401);
  if (object(result) && result.ok === false && result.error === "capacity_exceeded") return response({ ok: false, error: "capacity_exceeded" }, 503);
  if (!object(result) || result.ok !== true || result.consent_id !== input.consent_id) throw new Error("unconfirmed_duty_result");
  if (revoke) return response({ ok: true, consent_id: result.consent_id });
  if (!uuid(result.registration_id) || !uuid(result.generation) || !timestamp(result.server_time)
    || !timestamp(result.authority_expires_at) || Date.parse(result.authority_expires_at) <= Date.parse(result.server_time)) {
    throw new Error("invalid_duty_grant");
  }
  const projection = { ok: true, consent_id: result.consent_id, registration_id: result.registration_id,
    generation: result.generation, server_time: result.server_time, authority_expires_at: result.authority_expires_at };
  if (refresh) return response(projection);
  if (!Array.isArray(result.requests) || result.requests.length > 50) throw new Error("invalid_duty_snapshot");
  const seen = new Set();
  projection.requests = result.requests.map(row => {
    if (!object(row) || !uuid(row.request_id) || seen.has(row.request_id) || !timestamp(row.expires_at)
      || Date.parse(row.expires_at) <= Date.parse(result.server_time)) throw new Error("invalid_duty_request");
    seen.add(row.request_id);
    return { request_id: row.request_id, expires_at: row.expires_at };
  });
  return response(projection);
}
