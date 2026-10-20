import { UUID, object, readJson, response } from "../_shared/pos-order-alert.mjs";
import { scheduleInstantWake } from "../web-order-submit/instant-wake.mjs";

const ERRORS = new Set(["invalid_session", "permission_denied", "invalid_request", "not_found", "decision_conflict",
  "request_expired", "ordering_unavailable", "shift_required", "item_unavailable",
  "modifier_selection_invalid", "quote_changed", "order_rejected"]);
const validReason = (v) => typeof v === "string" && v === v.trim()
  && [...v].length >= 1 && [...v].length <= 240 && !/[\x00-\x1f\x7f\uD800-\uDFFF]/u.test(v);

function configuration(getEnv) {
  const base = getEnv("SUPABASE_URL");
  const publicKey = getEnv("SUPABASE_ANON_KEY");
  if (typeof publicKey !== "string" || !publicKey || /\s/.test(publicKey)) return null;
  let url;
  try { url = new URL(base); } catch { return null; }
  const local = url.protocol === "http:" && (["localhost", "127.0.0.1", "[::1]"].includes(url.hostname)
    || (url.hostname === "kong" && url.port === "8000"));
  if ((url.protocol !== "https:" && !local) || url.username || url.password || url.search || url.hash
    || !["", "/"].includes(url.pathname)) return null;
  return { base: url.origin, publicKey };
}

function validInput(input) {
  if (!object(input) || !["accept", "reject"].includes(input.action)) return false;
  const keys = ["action", "pin_session_id", "device_id", "device_session_token", "request_id", "decision_id",
    ...(input.action === "reject" ? ["reason"] : [])];
  return Object.keys(input).length === keys.length && keys.every((key) => Object.hasOwn(input, key))
    && ["pin_session_id", "device_id", "request_id", "decision_id"].every((key) => UUID.test(input[key] ?? ""))
    && typeof input.device_session_token === "string" && input.device_session_token.length <= 4096
    && input.device_session_token.trim().length > 0 && !/[\x00-\x1f\x7f]/.test(input.device_session_token)
    && (input.action !== "reject" || validReason(input.reason));
}

function projectResult(result, input) {
  if (!object(result)) return null;
  if (result.ok === false && ERRORS.has(result.error)) {
    return { ok: false, error: result.error, ...(result.entity === "web_order_request" ? { entity: result.entity } : {}) };
  }
  const expected = input.action === "accept" ? "accepted" : "rejected";
  if (result.ok !== true || result.request_id !== input.request_id || result.status !== expected
    || typeof result.replayed !== "boolean" || !UUID.test(result.decision_id ?? "")
    || (expected === "accepted" ? !UUID.test(result.canonical_order_id ?? "") : result.canonical_order_id !== null)
    || (!result.replayed && result.decision_id !== input.decision_id)) return null;
  return { ok: true, request_id: result.request_id, status: result.status,
    canonical_order_id: result.canonical_order_id, decision_id: result.decision_id, replayed: result.replayed };
}

/** Native decision boundary. REST validates the real caller JWT; SQL validates
 * device/PIN/tenant authority. No service-role impersonation or write retry. */
export function createHandler({ getEnv, fetchImpl = globalThis.fetch, waitUntil, now = Date.now,
  timeoutMs = 15_000, wakeTimeoutMs = 5000 } = {}) {
  return async function handler(request) {
    let controller; let timer;
    try {
      if (request.method !== "POST") return response({ ok: false, error: "method_not_allowed" }, 405);
      if (request.headers.has("origin")) return response({ ok: false, error: "origin_not_allowed" }, 403);
      const url = new URL(request.url);
      if (url.search || !["/", "/pos-web-order-decision", "/functions/v1/pos-web-order-decision"].includes(url.pathname)) {
        return response({ ok: false, error: "not_found" }, 404);
      }
      const authorization = request.headers.get("authorization");
      if (typeof authorization !== "string" || authorization.length > 8192
        || !/^Bearer [A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(authorization)) {
        return response({ ok: false, error: "invalid_session" }, 401);
      }
      if (!/^application\/json(?:\s*;\s*charset\s*=\s*(?:utf-8|"utf-8"))?\s*$/i.test(request.headers.get("content-type") ?? "")
        || (request.headers.has("content-encoding") && request.headers.get("content-encoding") !== "identity")) {
        return response({ ok: false, error: "invalid_request" }, 400);
      }
      const input = await readJson(request, 8192);
      if (!validInput(input)) return response({ ok: false, error: "invalid_request" }, 400);
      const config = configuration(getEnv);
      if (!config) return response({ ok: false, error: "unavailable" }, 503);
      const args = Object.fromEntries(["pin_session_id", "device_id", "device_session_token", "request_id", "decision_id"]
        .map((key) => [`p_${key}`, input[key]]));
      if (input.action === "reject") args.p_reason = input.reason;
      const rpc = input.action === "accept" ? "pos_accept_web_order" : "pos_reject_web_order_customer";
      controller = new AbortController();
      const operation = (async () => {
        const upstream = await fetchImpl(`${config.base}/rest/v1/rpc/${rpc}`, {
          method: "POST", headers: { "Content-Type": "application/json", "Accept": "application/json",
            "Accept-Profile": "public", "Content-Profile": "public", apikey: config.publicKey, Authorization: authorization },
          body: JSON.stringify(args), redirect: "error", cache: "no-store", signal: controller.signal,
        });
        if (controller.signal.aborted) throw new Error("decision_unknown");
        if (!upstream.ok) {
          if (upstream.body) void upstream.body.cancel().catch(() => {});
          return { httpError: [401, 403].includes(upstream.status) ? 401 : 503 };
        }
        return projectResult(await readJson(upstream, 8192), input);
      })();
      const result = await Promise.race([operation, new Promise((_, reject) => {
        timer = setTimeout(() => { controller.abort(); reject(new Error("decision_unknown")); }, timeoutMs);
      })]);
      if (result?.httpError === 401) return response({ ok: false, error: "invalid_session" }, 401);
      if (!result || result.httpError) return response({ ok: false, error: "decision_outcome_unknown" }, 503);
      const output = response(result);
      // A valid REST response arrives after its database transaction committed.
      // Construct the response first; never await notification work or retry a decision.
      if (result.ok && result.replayed === false) {
        scheduleInstantWake({ getEnv, fetchImpl, waitUntil, now, timeoutMs: wakeTimeoutMs });
      }
      return output;
    } catch {
      // No raw exceptions, credentials, request body, contact or reason logging.
      return response({ ok: false, error: "decision_outcome_unknown" }, 503);
    } finally { clearTimeout(timer); controller?.abort(); }
  };
}
