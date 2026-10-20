import { configuration, constantSecret, object, readJson, response, rpc } from "../_shared/pos-order-alert.mjs";
import { serviceAccount, accessToken, send } from "./fcm.mjs";
import { dispatchPilot, sameDispatchPilot } from "../_shared/pos-order-alert-pilot.mjs";
export function createHandler({ getEnv, fetchImpl = globalThis.fetch, cryptoImpl = globalThis.crypto,
  now = Date.now, timeoutMs = 5000, tokenProvider = accessToken } = {}) {
  return async function handler(request) {
    try {
      if (request.method !== "POST") return response({ ok: false, error: "method_not_allowed" }, 405);
      if (request.headers.has("origin")) return response({ ok: false, error: "origin_not_allowed" }, 403);
      if (getEnv("POS_ORDER_ALERTS_ENABLED") !== "true") return response({ ok: false, error: "disabled" }, 503);
      const match = /^Bearer ([0-9a-f]{64})$/.exec(request.headers.get("authorization") ?? "");
      if (!match || !await constantSecret(match[1], getEnv("POS_ORDER_ALERT_WORKER_SECRET"), cryptoImpl)) return response({ ok: false, error: "unauthorized" }, 401);
      const input = await readJson(request);
      if (!object(input) || Object.keys(input).length !== 0 || new URL(request.url).search) return response({ ok: false, error: "invalid_request" }, 400);
      // ALL callers, including Cron and instant wakes, need Edge-side authority.
      const pilot = dispatchPilot(getEnv, now());
      if (!pilot) return response({ ok: false, error: "unavailable" }, 503);
      const config = configuration(getEnv); const account = serviceAccount(getEnv("POS_ORDER_ALERT_FCM_SERVICE_ACCOUNT"));
      if (!config || !account) return response({ ok: false, error: "unavailable" }, 503);
      // OAuth failure happens BEFORE queue claiming. No credential/token/PII
      // appears in responses, logs or metadata. Each invocation is bounded.
      const token = await tokenProvider(account, { fetchImpl, cryptoImpl, now, timeoutMs });
      if (!sameDispatchPilot(pilot, getEnv, now())) return response({ ok: false, error: "unavailable" }, 503);
      const batch = await rpc("pos_claim_order_alert_deliveries", { p_limit: 10 }, config, fetchImpl, timeoutMs);
      if (!object(batch) || batch.ok !== true || !Array.isArray(batch.deliveries) || batch.deliveries.length > 10) throw new Error("invalid_batch");
      let sent = 0; let deferred = 0;
      for (const delivery of batch.deliveries) {
        // Expiry/reconfiguration cannot authorize a later send from this batch.
        // Leave unsent leases intact for the existing later reconciliation path.
        if (!sameDispatchPilot(pilot, getEnv, now())) return response({ ok: false, error: "unavailable" }, 503);
        let outcome = "retry";
        try { outcome = await send(account, token, delivery, { fetchImpl, now, timeoutMs }); } catch { /* Unknown HTTP outcome is only a duplicate-safe hint retry. */ }
        const result = await rpc("pos_finish_order_alert_delivery", { p_delivery_id: delivery.delivery_id,
          p_lease_id: delivery.lease_id, p_outcome: outcome }, config, fetchImpl, timeoutMs);
        if (!object(result) || result.ok !== true) throw new Error("finish_uncertain");
        if (outcome === "sent") sent++; else deferred++;
      }
      return response({ ok: true, sent, deferred });
    } catch { return response({ ok: false, error: "unavailable" }, 503); }
  };
}
