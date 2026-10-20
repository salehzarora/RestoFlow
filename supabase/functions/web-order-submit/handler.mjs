import { RequestError } from "./errors.mjs";
import { readRequestJson, readStrictJson } from "./json.mjs";
import { hashStatusToken, validateRequest } from "./validation.mjs";
import { authorizeTestSubmission } from "./test-admission.mjs";
import { scheduleInstantWake } from "./instant-wake.mjs";

const DEFAULT_ORIGIN = "https://menu.bizbot.systems";
const PUBLIC_STATUSES = new Set(["pending", "expired", "accepted", "rejected"]);
const BUSINESS_ERRORS = new Map([
  ["invalid_request", 400], ["not_found", 404], ["ordering_unavailable", 503],
  ["idempotency_conflict", 409], ["item_unavailable", 422],
  ["modifier_selection_invalid", 422], ["menu_unavailable", 422],
  ["rate_limited", 429], ["capacity_reached", 429],
]);
const MAX_TOTAL_MINOR = 10_000_000;

function responseHeaders(origin) {
  const headers = new Headers({
    "Content-Type": "application/json; charset=utf-8",
    "Cache-Control": "no-store, max-age=0",
    "Pragma": "no-cache",
    "Referrer-Policy": "no-referrer",
    "X-Content-Type-Options": "nosniff",
    "Vary": "Origin",
  });
  if (origin) headers.set("Access-Control-Allow-Origin", origin);
  return headers;
}

function json(body, status, origin) {
  return new Response(JSON.stringify(body), { status, headers: responseHeaders(origin) });
}

function credentials(getEnv) {
  const base = getEnv("SUPABASE_URL");
  const serviceKey = getEnv("SUPABASE_SERVICE_ROLE_KEY");
  if (!base || !serviceKey) return null;
  let url;
  try { url = new URL(base); } catch { return null; }
  const localHttp = url.protocol === "http:" && ["localhost", "127.0.0.1", "[::1]"].includes(url.hostname);
  const localGateway = url.protocol === "http:" && url.hostname === "kong" && url.port === "8000";
  if (url.protocol !== "https:" && !localHttp && !localGateway) return null;
  if (url.username || url.password || url.search || url.hash || !["", "/"].includes(url.pathname)) return null;
  return { base: url.origin, serviceKey };
}

function publicResult(result, requestId) {
  if (!result || typeof result !== "object" || Array.isArray(result)) return null;
  if (result.ok === false) {
    const status = BUSINESS_ERRORS.get(result.error);
    return status ? { body: { ok: false, error: result.error }, status } : null;
  }
  if (result.ok !== true || result.request_id !== requestId || !PUBLIC_STATUSES.has(result.status)) return null;
  if (typeof result.expires_at !== "string" || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$/.test(result.expires_at) || !Number.isFinite(Date.parse(result.expires_at))) return null;
  if (typeof result.replayed !== "boolean") return null;
  const totals = result.totals;
  if (!totals || typeof totals !== "object" || Array.isArray(totals) || totals.currency_code !== "ILS") return null;
  const amounts = [totals.subtotal_minor, totals.tax_total_minor, totals.grand_total_minor];
  if (amounts.some((amount) => !Number.isSafeInteger(amount) || amount < 0 || amount > MAX_TOTAL_MINOR)) return null;
  if (totals.subtotal_minor + totals.tax_total_minor !== totals.grand_total_minor) return null;
  // Project explicitly: even a future upstream field cannot expose customer data or capabilities.
  return {
    status: 200,
    body: {
      ok: true, request_id: requestId, status: result.status, expires_at: result.expires_at,
      totals: { currency_code: "ILS", subtotal_minor: totals.subtotal_minor, tax_total_minor: totals.tax_total_minor, grand_total_minor: totals.grand_total_minor },
      replayed: result.replayed,
    },
  };
}

async function callRpc({ input, configuration, fetchImpl, timeoutMs, tokenHash, testPermit, pilotSubmission }) {
  const rpc = input.action === "submit" ? (testPermit ? "submit_web_order_test_request" : pilotSubmission ? "submit_web_order_pilot_request" : "submit_web_order_live_request") : "get_web_order_request_status";
  const args = { p_slug: input.slug, p_client_request_id: input.request_id, p_status_token_hash: tokenHash };
  if (input.action === "submit") args.p_order = input.order;
  if (testPermit) Object.assign(args, {
    p_test_organization_id: testPermit.organizationId, p_test_restaurant_id: testPermit.restaurantId,
    p_test_branch_id: testPermit.branchId, p_test_request_id: testPermit.requestId,
    p_test_not_before: testPermit.notBefore, p_test_expires_at: testPermit.expiresAt,
  });
  const controller = new AbortController();
  let timer;
  const deadline = new Promise((_, reject) => {
    timer = setTimeout(() => {
      controller.abort();
      reject(new Error("rpc_timeout"));
    }, timeoutMs);
  });
  try {
    return await Promise.race([
      (async () => {
        // Customer Authorization/apikey headers are deliberately never copied here.
        const upstream = await fetchImpl(`${configuration.base}/rest/v1/rpc/${rpc}`, {
          method: "POST",
          headers: {
            "Content-Type": "application/json", "Accept": "application/json",
            "Accept-Profile": "public", "Content-Profile": "public",
            "apikey": configuration.serviceKey, "Authorization": `Bearer ${configuration.serviceKey}`,
          },
          body: JSON.stringify(args), redirect: "error", cache: "no-store", signal: controller.signal,
        });
        if (!upstream.ok) {
          if (upstream.body) void upstream.body.cancel().catch(() => {});
          return { failed: true, status: [429, 503, 504].includes(upstream.status) ? 503 : 502 };
        }
        const result = publicResult(await readStrictJson(upstream), input.request_id);
        return result ?? { failed: true, status: 502 };
      })(),
      deadline,
    ]);
  } catch {
    // Neither upstream response text nor exception messages are safe public diagnostics.
    return { failed: true, status: controller.signal.aborted ? 503 : 502 };
  } finally {
    clearTimeout(timer);
  }
}

/** Dependency injection is only for offline tests; production uses built-in fetch/WebCrypto. */
export function createHandler({ getEnv, fetchImpl = globalThis.fetch, cryptoImpl = globalThis.crypto, timeoutMs = 10_000, now = Date.now,
  waitUntil, wakeTimeoutMs = 5000 } = {}) {
  if (typeof getEnv !== "function") throw new TypeError("getEnv is required");
  return async function handler(request) {
    let origin;
    try {
      const incomingOrigin = request.headers.get("origin");
      const allowedOrigin = getEnv("WEB_ORDERS_ALLOWED_ORIGIN") ?? DEFAULT_ORIGIN;
      if (incomingOrigin !== null && incomingOrigin !== allowedOrigin) return json({ ok: false, error: "origin_not_allowed" }, 403);
      origin = incomingOrigin;
      if (request.method === "OPTIONS") {
        const requestedMethod = request.headers.get("access-control-request-method");
        const requestedHeaders = (request.headers.get("access-control-request-headers") ?? "").toLowerCase().split(",").map((value) => value.trim()).filter(Boolean);
        const allowedHeaders = new Set(["content-type", "authorization", "apikey", "x-client-info"]);
        if ((requestedMethod !== null && requestedMethod !== "POST") || requestedHeaders.some((value) => !allowedHeaders.has(value))) {
          return json({ ok: false, error: "invalid_preflight" }, 403, origin);
        }
        const headers = responseHeaders(origin);
        headers.set("Access-Control-Allow-Methods", "POST, OPTIONS");
        headers.set("Access-Control-Allow-Headers", "content-type, authorization, apikey, x-client-info");
        headers.set("Access-Control-Max-Age", "600");
        return new Response(null, { status: 204, headers });
      }
      if (request.method !== "POST") {
        const response = json({ ok: false, error: "method_not_allowed" }, 405, origin);
        response.headers.set("Allow", "POST, OPTIONS");
        return response;
      }
      const input = validateRequest(await readRequestJson(request));
      let testPermit = null;
      let pilotSubmission = false;
      const enabledGates = ["WEB_ORDERS_ENABLED", "WEB_ORDERS_TEST_ENABLED", "WEB_ORDERS_PILOT_ENABLED"]
        .filter((name) => getEnv(name) === "true").length;
      if (input.action === "submit" && enabledGates > 1) {
        return json({ ok: false, error: "ordering_unavailable" }, 503, origin);
      }
      if (input.action === "submit" && getEnv("WEB_ORDERS_ENABLED") !== "true") {
        testPermit = await authorizeTestSubmission({ input, request, getEnv, cryptoImpl, now });
        // This is routing, never admission authority. The private database pilot
        // enforces exact branch, approved contact, expiry and one atomic request.
        pilotSubmission = !testPermit && getEnv("WEB_ORDERS_PILOT_ENABLED") === "true" && input.slug === "mapsburger";
        if (!testPermit && !pilotSubmission) return json({ ok: false, error: "ordering_unavailable" }, 503, origin);
      }
      const configuration = credentials(getEnv);
      if (!configuration) return json({ ok: false, error: input.action === "submit" ? "ordering_unavailable" : "status_unavailable", uncertain: false }, 503, origin);
      const tokenHash = await hashStatusToken(input.status_token, cryptoImpl);
      const result = await callRpc({ input, configuration, fetchImpl, timeoutMs, tokenHash, testPermit, pilotSubmission });
      if (result.failed) {
        return json({ ok: false, error: input.action === "submit" ? "submission_outcome_unknown" : "status_unavailable", request_id: input.request_id, uncertain: input.action === "submit" }, result.status, origin);
      }
      const response = json(result.body, result.status, origin);
      // Only a validated, committed NEW normal-live Maps Burger pending result.
      // Construct the unchanged public response first; never await notification work.
      if (input.action === "submit" && input.slug === "mapsburger" && !testPermit && !pilotSubmission
        && result.body.ok === true && result.body.status === "pending" && result.body.replayed === false) {
        scheduleInstantWake({ getEnv, waitUntil, fetchImpl, now, timeoutMs: wakeTimeoutMs });
      }
      return response;
    } catch (error) {
      if (error instanceof RequestError) return json({ ok: false, error: error.code }, error.status, origin);
      return json({ ok: false, error: "service_unavailable" }, 503, origin);
    }
  };
}
