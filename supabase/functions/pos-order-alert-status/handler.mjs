import { configuration, HEX_SECRET, UUID, timestamp, object, hash, readJson, response, rpc } from "../_shared/pos-order-alert.mjs";

export function createHandler({ getEnv, fetchImpl = globalThis.fetch, cryptoImpl = globalThis.crypto, timeoutMs = 5000 } = {}) {
  return async function handler(request) {
    try {
      if (request.method !== "POST") return response({ ok: false, error: "method_not_allowed" }, 405);
      // Native-only delegation: no CORS grant or cookie/session fallback.
      if (request.headers.has("origin")) return response({ ok: false, error: "origin_not_allowed" }, 403);
      const url = new URL(request.url);
      const disable = url.pathname === "/disable" || url.pathname.endsWith("/pos-order-alert-status/disable");
      const status = url.pathname === "/" || url.pathname.endsWith("/pos-order-alert-status");
      if ((!disable && !status) || url.search) return response({ ok: false, error: "not_found" }, 404);
      // Revocation remains available while alerts are OFF. A status read cannot
      // activate, renew, register, Accept, Reject or print anything.
      if (!disable && getEnv("POS_ORDER_ALERTS_ENABLED") !== "true") return response({ ok: false, error: "disabled" }, 503);
      const match = /^Bearer ([0-9a-f]{64})$/.exec(request.headers.get("authorization") ?? "");
      if (!match || !HEX_SECRET.test(match[1])) return response({ ok: false, error: "unauthorized" }, 401);
      const input = await readJson(request);
      if (!object(input) || Object.keys(input).length !== 1 || !UUID.test(input.installation_id ?? "")) return response({ ok: false, error: "invalid_request" }, 400);
      const config = configuration(getEnv);
      if (!config) return response({ ok: false, error: "unavailable" }, 503);
      const result = await rpc(disable ? "pos_disable_order_alert" : "pos_order_alert_status", {
        p_installation_id: input.installation_id, p_status_secret_hash: await hash(match[1], cryptoImpl),
      }, config, fetchImpl, timeoutMs);
      if (!object(result) || result.ok !== true) {
        return response({ ok: false, error: result?.error === "capacity_exceeded" ? "capacity_exceeded" : "unauthorized" }, result?.error === "capacity_exceeded" ? 503 : 401);
      }
      if (disable) return response({ ok: true });
      if (!UUID.test(result.registration_id ?? "") || !timestamp(result.server_time) || !timestamp(result.authority_expires_at) || !Array.isArray(result.requests) || result.requests.length > 50) throw new Error("invalid_result");
      const ids = new Set(); const requests = result.requests.map((row) => {
        if (!object(row) || !UUID.test(row.request_id ?? "") || !timestamp(row.expires_at) || ids.has(row.request_id)
          || Date.parse(row.expires_at) <= Date.parse(result.server_time)) throw new Error("invalid_result");
        ids.add(row.request_id); return { request_id: row.request_id, expires_at: row.expires_at };
      });
      if (Date.parse(result.authority_expires_at) <= Date.parse(result.server_time)) throw new Error("expired_authority");
      return response({ ok: true, server_time: result.server_time, registration_id: result.registration_id, authority_expires_at: result.authority_expires_at, requests });
    } catch { return response({ ok: false, error: "unavailable" }, 503); }
  };
}
