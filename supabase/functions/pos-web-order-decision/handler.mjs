import { UUID, object, readJson, response } from "../_shared/pos-order-alert.mjs";
import { scheduleInstantWake } from "../web-order-submit/instant-wake.mjs";

const ERRORS = new Set(["invalid_session", "permission_denied", "invalid_request", "not_found", "decision_conflict",
  "request_expired", "ordering_unavailable", "shift_required", "item_unavailable",
  "modifier_selection_invalid", "quote_changed", "order_rejected"]);
const validReason = (v) => typeof v === "string" && v === v.trim()
  && [...v].length >= 1 && [...v].length <= 240 && !/[\x00-\x1f\x7f\uD800-\uDFFF]/u.test(v);
// Existing product origins, docs/DEPLOYMENT.md §5.1. Pairing/session storage on
// the legacy origin must keep working; arbitrary previews are not new authority.
const PRODUCT_ORIGINS = new Set(["https://app.bizbot.systems", "https://resto-flow-phi.vercel.app"]);
const CORS_HEADERS = ["authorization", "apikey", "content-type", "x-client-info"];

function decisionResponse(body, status, origin) {
  const result = response(body, status);
  result.headers.set("Vary", "Origin");
  if (origin) {
    result.headers.set("Access-Control-Allow-Origin", origin);
    result.headers.set("Access-Control-Allow-Methods", "POST, OPTIONS");
    result.headers.set("Access-Control-Allow-Headers", CORS_HEADERS.join(", "));
    result.headers.set("Access-Control-Max-Age", "600");
  }
  // No Allow-Credentials, cookie authentication or caller-supplied API key.
  return result;
}

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
    ...(input.action === "reject" ? ["reason"] : []),
    ...(input.action === "accept" && Object.hasOwn(input, "preparation_minutes") ? ["preparation_minutes"] : [])];
  return Object.keys(input).length === keys.length && keys.every((key) => Object.hasOwn(input, key))
    && ["pin_session_id", "device_id", "request_id", "decision_id"].every((key) => UUID.test(input[key] ?? ""))
    && typeof input.device_session_token === "string" && input.device_session_token.length <= 4096
    && input.device_session_token.trim().length > 0 && !/[\x00-\x1f\x7f]/.test(input.device_session_token)
    && (input.action !== "reject" || validReason(input.reason))
    && (!Object.hasOwn(input, "preparation_minutes") || (Number.isInteger(input.preparation_minutes)
      && input.preparation_minutes >= 1 && input.preparation_minutes <= 240));
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

/** POS decision boundary. REST validates the real caller JWT; SQL validates
 * device/PIN/tenant authority. No service-role impersonation or write retry. */
export function createHandler({ getEnv, fetchImpl = globalThis.fetch, waitUntil, now = Date.now,
  timeoutMs = 15_000, wakeTimeoutMs = 5000 } = {}) {
  return async function handler(request) {
    let controller; let timer; let origin;
    const reply = (body, status = 200) => decisionResponse(body, status, origin);
    try {
      const incomingOrigin = request.headers.get("origin");
      if (incomingOrigin !== null && !PRODUCT_ORIGINS.has(incomingOrigin)) return reply({ ok: false, error: "origin_not_allowed" }, 403);
      origin = incomingOrigin;
      const url = new URL(request.url);
      if (url.search || !["/", "/pos-web-order-decision", "/functions/v1/pos-web-order-decision"].includes(url.pathname)) {
        return reply({ ok: false, error: "not_found" }, 404);
      }
      if (request.method === "OPTIONS") {
        const requestedHeaders = (request.headers.get("access-control-request-headers") ?? "")
          .toLowerCase().split(",").map((v) => v.trim()).filter(Boolean);
        if (!origin || request.headers.get("access-control-request-method") !== "POST"
          || requestedHeaders.some((v) => !CORS_HEADERS.includes(v))) return reply({ ok: false, error: "invalid_preflight" }, 403);
        return new Response(null, { status: 204, headers: reply(null).headers });
      }
      if (request.method !== "POST") return reply({ ok: false, error: "method_not_allowed" }, 405);
      const authorization = request.headers.get("authorization");
      if (typeof authorization !== "string" || authorization.length > 8192
        || !/^Bearer [A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(authorization)) {
        return reply({ ok: false, error: "invalid_session" }, 401);
      }
      if (!/^application\/json(?:\s*;\s*charset\s*=\s*(?:utf-8|"utf-8"))?\s*$/i.test(request.headers.get("content-type") ?? "")
        || (request.headers.has("content-encoding") && request.headers.get("content-encoding") !== "identity")) {
        return reply({ ok: false, error: "invalid_request" }, 400);
      }
      const input = await readJson(request, 8192);
      if (!validInput(input)) return reply({ ok: false, error: "invalid_request" }, 400);
      const config = configuration(getEnv);
      if (!config) return reply({ ok: false, error: "unavailable" }, 503);
      const args = Object.fromEntries(["pin_session_id", "device_id", "device_session_token", "request_id", "decision_id"]
        .map((key) => [`p_${key}`, input[key]]));
      if (input.action === "reject") args.p_reason = input.reason;
      const hasEstimate = Object.hasOwn(input, "preparation_minutes");
      if (hasEstimate) args.p_preparation_minutes = input.preparation_minutes;
      const rpc = input.action === "accept"
        ? (hasEstimate ? "pos_accept_web_order_with_eta" : "pos_accept_web_order")
        : "pos_reject_web_order_customer";
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
      if (result?.httpError === 401) return reply({ ok: false, error: "invalid_session" }, 401);
      if (!result || result.httpError) return reply({ ok: false, error: "decision_outcome_unknown" }, 503);
      const output = reply(result);
      // A valid REST response arrives after its database transaction committed.
      // Construct the response first; never await notification work or retry a decision.
      if (result.ok && result.replayed === false) {
        scheduleInstantWake({ getEnv, fetchImpl, waitUntil, now, timeoutMs: wakeTimeoutMs });
      }
      return output;
    } catch {
      // No raw exceptions, credentials, request body, contact or reason logging.
      return reply({ ok: false, error: "decision_outcome_unknown" }, 503);
    } finally { clearTimeout(timer); controller?.abort(); }
  };
}
