import test from "node:test";
import assert from "node:assert/strict";
import { createHash, webcrypto } from "node:crypto";
import { createHandler } from "../handler.mjs";
import { projectAcceptanceEta } from "../acceptance-eta.mjs";

const HEADER = "X-BIZBOT-Order-Response-Version";
const ORIGIN = "https://menu.bizbot.systems";
const BASE = "https://synthetic-project.supabase.co";
const ID = "36600000-0000-4000-8000-000000000001";
const TOKEN = Buffer.alloc(32, 73).toString("base64url");
const KEY = "synthetic-service-only";
const statusInput = () => ({ action: "status", slug: "synthetic", request_id: ID, status_token: TOKEN });
const submitInput = () => ({ ...statusInput(), action: "submit", order: { order_type: "takeaway",
  customer: { name: "Synthetic Customer", phone: "+972501234567" },
  items: [{ menu_item_id: "36600000-0000-4000-8000-000000000002", quantity: 1 }] } });
const success = (extra = {}) => ({ ok: true, request_id: ID, status: "accepted", expires_at: "2026-10-22T23:15:00Z",
  totals: { currency_code: "ILS", subtotal_minor: 1200, tax_total_minor: 0, grand_total_minor: 1200 }, replayed: false, ...extra });
const eta = (extra = {}) => ({ preparation_minutes: 15, accepted_at: "2026-10-22T23:55:00.123456Z",
  ready_at: "2026-10-23T00:10:00.123456Z", timezone: "Asia/Jerusalem", ...extra });
function fixture({ upstream = success(), fetch, env = {}, timeoutMs = 50, cryptoImpl = webcrypto } = {}) {
  const calls = []; const tasks = [];
  const config = { SUPABASE_URL: BASE, SUPABASE_SERVICE_ROLE_KEY: KEY, WEB_ORDERS_ENABLED: "true", ...env };
  const handler = createHandler({ getEnv: (key) => config[key], timeoutMs, cryptoImpl,
    waitUntil: (promise) => tasks.push(promise), fetchImpl: async (url, init) => {
      calls.push({ url, init }); return fetch ? fetch(url, init) : Response.json(upstream);
    } });
  const run = async (body = statusInput(), version = "2", options = {}) => {
    const headers = new Headers({ "content-type": "application/json", origin: ORIGIN, ...options.headers });
    if (version !== null) headers.set(HEADER, version);
    const response = await handler(new Request("https://edge.test/functions/v1/web-order-submit", {
      method: options.method ?? "POST", headers,
      ...((options.method ?? "POST") === "POST" ? { body: typeof body === "string" ? body : JSON.stringify(body) } : {}) }));
    return { response, body: response.status === 204 ? null : await response.json() };
  };
  return { calls, tasks, run, handler };
}
function assertNegotiated(response, ack = "2") {
  assert.equal(response.headers.get(HEADER), ack);
  assert.equal(response.headers.get("vary"), `Origin, ${HEADER}`);
  assert.equal(response.headers.get("access-control-expose-headers"), HEADER);
  assert.equal(response.headers.get("access-control-allow-credentials"), null);
  assert.equal(response.headers.get("cache-control"), "no-store, max-age=0");
  assert.equal(response.headers.get("pragma"), "no-cache");
}

test("v2 status calls the new reader once with only server authority and the original capability hash", async () => {
  const f = fixture({ upstream: success({ acceptance_eta: eta(), canonical_order_id: "private-order",
    device_id: "private-device", customer: { phone: "private-phone" }, status_token: TOKEN }) });
  const output = await f.run(statusInput(), "2", { headers: { authorization: "Bearer browser-private", apikey: "browser-key" } });
  assertNegotiated(output.response); assert.equal(output.response.status, 200);
  assert.deepEqual(output.body, success({ acceptance_eta: eta() }));
  assert.equal(f.calls.length, 1); const call = f.calls[0];
  assert.equal(call.url, `${BASE}/rest/v1/rpc/get_web_order_request_status_v2`);
  assert.deepEqual(JSON.parse(call.init.body), { p_slug: "synthetic", p_client_request_id: ID,
    p_status_token_hash: createHash("sha256").update(TOKEN).digest("hex") });
  assert.equal(call.init.headers.Authorization, `Bearer ${KEY}`); assert.equal(call.init.headers.apikey, KEY);
  assert.equal(call.init.redirect, "error"); assert.equal(call.init.cache, "no-store");
  assert.equal(f.tasks.length, 0, "status never schedules an order/notification write");
  assert.equal(/private|synthetic-service|browser|status_token|canonical_order_id|device_id/.test(JSON.stringify(output.body)), false);
});

for (const version of [null, "1"]) {
  test(`legacy header ${version ?? "absent"} always strips ETA from all statuses and submit replay`, async () => {
    // This strict legacy decoder represents an already-open old tab: it has no
    // optional ETA key and does not reload or mint another request/capability.
    const strictOldDecode = (body) => {
      assert.deepEqual(Object.keys(body).sort(), Object.keys(success()).sort()); return body.status;
    };
    for (const status of ["pending", "accepted", "rejected", "expired"]) {
      const f = fixture({ upstream: success({ status, acceptance_eta: { malformed: "private" } }) });
      const output = await f.run(statusInput(), version);
      assert.equal(output.response.status, 200); assertNegotiated(output.response, null);
      assert.deepEqual(output.body, success({ status })); assert.equal(strictOldDecode(output.body), status);
      assert.equal(f.calls[0].url, `${BASE}/rest/v1/rpc/get_web_order_request_status`);
    }
    const f = fixture({ upstream: success({ replayed: true, acceptance_eta: eta() }) });
    const output = await f.run(submitInput(), version);
    assert.deepEqual(output.body, success({ replayed: true })); strictOldDecode(output.body);
    assert.equal(f.calls.length, 1); assert.equal(f.calls[0].url, `${BASE}/rest/v1/rpc/submit_web_order_platform_request`);
  });
}

for (const status of ["pending", "accepted", "rejected", "expired"]) {
  test(`v2 ${status} without ETA acknowledges negotiated optional absence`, async () => {
    const extra = status === "rejected" ? { customer_rejection_reason: "Unavailable" } : {};
    const f = fixture({ upstream: success({ status, ...extra }) }); const output = await f.run();
    assert.equal(output.response.status, 200); assertNegotiated(output.response);
    assert.deepEqual(output.body, success({ status, ...extra })); assert.equal(f.calls.length, 1);
  });
}

for (const [error, status] of [["invalid_request", 400], ["not_found", 404], ["ordering_unavailable", 503],
  ["idempotency_conflict", 409], ["item_unavailable", 422], ["modifier_selection_invalid", 422],
  ["menu_unavailable", 422], ["rate_limited", 429], ["capacity_reached", 429]]) {
  test(`v2 fixed ${error} error retains ACK without upstream details or an additional RPC`, async () => {
    const f = fixture({ upstream: { ok: false, error, details: "private", acceptance_eta: eta() } });
    const output = await f.run(); assertNegotiated(output.response); assert.equal(output.response.status, status);
    assert.deepEqual(output.body, { ok: false, error }); assert.equal(f.calls.length, 1);
  });
}

for (const version of ["", "0", "02", "3", "2, 2", "1,2", "2.0", "null", "unsupported-private"]) {
  test(`malformed or unsupported version ${JSON.stringify(version)} denies before RPC and never acknowledges`, async () => {
    const f = fixture(); const output = await f.run(statusInput(), version);
    assert.equal(output.response.status, 400); assertNegotiated(output.response, null);
    assert.deepEqual(output.body, { ok: false, error: "invalid_request" }); assert.equal(f.calls.length, 0);
  });
}

test("case-insensitive header names work; duplicate header values cannot select an RPC", async () => {
  const f = fixture(); const headers = new Headers({ "content-type": "application/json", "x-bizbot-order-response-version": "2" });
  const response = await f.handler(new Request("https://edge.test/web-order-submit", { method: "POST", headers, body: JSON.stringify(statusInput()) }));
  assertNegotiated(response); assert.equal(f.calls.length, 1);
  headers.append(HEADER, "2");
  const denied = await f.handler(new Request("https://edge.test/web-order-submit", { method: "POST", headers, body: JSON.stringify(statusInput()) }));
  assert.equal(denied.status, 400); assertNegotiated(denied, null); assert.equal(f.calls.length, 1);
});

test("submit-v2 is refused before submission, capability hash, status enrichment or wake", async () => {
  const f = fixture({ cryptoImpl: { subtle: { digest() { throw new Error("must not hash"); } } } });
  const output = await f.run(submitInput()); assert.equal(output.response.status, 400); assertNegotiated(output.response, null);
  assert.deepEqual(output.body, { ok: false, error: "invalid_request" }); assert.equal(f.calls.length, 0); assert.equal(f.tasks.length, 0);
});

test("known status action gets ACK even on validation failure; unreadable or unknown action never does", async () => {
  for (const body of [{ ...statusInput(), status_token: "invalid-private" }, { ...statusInput(), extra: true }, { action: "status" }]) {
    const f = fixture(); const output = await f.run(body);
    assert.equal(output.response.status, 400); assertNegotiated(output.response); assert.equal(f.calls.length, 0);
  }
  for (const body of ["{", "null", "[]", "{}", '{"action":"other"}', '{"action":"status","action":"submit"}']) {
    const f = fixture(); const output = await f.run(body); assertNegotiated(output.response, null); assert.equal(f.calls.length, 0);
  }
  for (const options of [{ method: "GET" }, { headers: { origin: "https://attacker.test" } },
    { headers: { "content-type": "text/plain" } }, { headers: { "content-encoding": "gzip" } }]) {
    const f = fixture(); const output = await f.run(statusInput(), "2", options);
    assertNegotiated(output.response, null); assert.equal(f.calls.length, 0);
  }
});

test("CORS preflight adds only the version header, exposes its ACK and retains existing cache/origin policy", async () => {
  const f = fixture(); const output = await f.run(undefined, "2", { method: "OPTIONS", headers: {
    "access-control-request-method": "POST", "access-control-request-headers": "content-type,authorization,apikey,x-client-info,X-BIZBOT-Order-Response-Version" } });
  assert.equal(output.response.status, 204); assertNegotiated(output.response, null);
  assert.equal(output.response.headers.get("access-control-allow-headers"), "content-type, authorization, apikey, x-client-info, x-bizbot-order-response-version");
  assert.equal(output.response.headers.get("access-control-allow-origin"), ORIGIN);
  assert.equal(output.response.headers.get("access-control-max-age"), "600"); assert.equal(f.calls.length, 0);
  const denied = await f.run(undefined, "2", { method: "OPTIONS", headers: { "access-control-request-headers": "x-arbitrary" } });
  assert.equal(denied.response.status, 403); assertNegotiated(denied.response, null); assert.equal(f.calls.length, 0);
});

test("v2 missing server configuration and post-action hash failure both retain ACK without network", async () => {
  for (const options of [{ env: { SUPABASE_SERVICE_ROLE_KEY: "" } },
    { cryptoImpl: { subtle: { digest() { throw new Error("synthetic-private"); } } } }]) {
    const f = fixture(options); const output = await f.run(); assertNegotiated(output.response);
    assert.equal(output.response.status, 503); assert.equal(f.calls.length, 0);
    assert.equal(JSON.stringify(output.body).includes("synthetic-private"), false);
  }
});

for (const phase of ["headers", "body"]) {
  test(`v2 ${phase} timeout acknowledges negotiated unavailable, not success or legacy fallback`, async () => {
    const f = fixture({ timeoutMs: 5, fetch: async () => phase === "headers" ? new Promise(() => {})
      : new Response(new ReadableStream({ start() {} })) });
    const output = await f.run(); assertNegotiated(output.response); assert.equal(output.response.status, 503);
    assert.deepEqual(output.body, { ok: false, error: "status_unavailable", request_id: ID, uncertain: false });
    assert.equal(f.calls.length, 1); assert.equal(f.calls[0].init.signal.aborted, true); assert.equal(f.tasks.length, 0);
  });
}

test("v2 upstream failures are sanitized, acknowledged, bounded and never retried", async () => {
  for (const fetch of [() => { throw new Error("private-capability-connection"); },
    async () => new Response("private", { status: 403 }), async () => new Response("private", { status: 503 }),
    async () => new Response("{"), async () => Response.json(success({ request_id: "private-other-request" }))]) {
    const f = fixture({ fetch }); const output = await f.run(); assertNegotiated(output.response);
    assert.equal([502, 503].includes(output.response.status), true); assert.equal(output.body.error, "status_unavailable");
    assert.equal(JSON.stringify(output.body).includes("private"), false); assert.equal(f.calls.length, 1); assert.equal(f.tasks.length, 0);
  }
});

test("UTC microseconds are preserved and alternate UTC spellings canonicalize without changing the instant", () => {
  assert.deepEqual(projectAcceptanceEta(eta({ accepted_at: "2026-10-22T23:55:00.123456+00:00",
    ready_at: "2026-10-23T00:10:00.123456+00:00" })), eta());
  assert.deepEqual(projectAcceptanceEta(eta({ accepted_at: "2026-10-22T23:55:00Z", ready_at: "2026-10-23T00:10:00+00:00" })),
    eta({ accepted_at: "2026-10-22T23:55:00.000000Z", ready_at: "2026-10-23T00:10:00.000000Z" }));
  for (const zone of ["UTC", "Asia/Jerusalem", "America/New_York", "Etc/GMT+3"]) {
    assert.equal(projectAcceptanceEta(eta({ timezone: zone })).timezone, zone);
  }
  assert.notEqual(projectAcceptanceEta(eta({ preparation_minutes: 1, accepted_at: "2024-02-29T23:59:59.999999Z",
    ready_at: "2024-03-01T00:00:59.999999Z" })), null);
});

const invalidEtas = [null, [], "private", {}, { ...eta(), extra: "private" },
  ...Object.keys(eta()).map((key) => { const value = eta(); delete value[key]; return value; }),
  ...[null, true, "15", 0, -1, 241, 1.5].map((preparation_minutes) => eta({ preparation_minutes })),
  ...["2026-02-29T23:55:00.123456Z", "2026-04-31T23:55:00.123456Z", "2026-10-22T24:55:00.123456Z",
    "2026-10-22T23:55:60.123456Z", "0000-10-22T23:55:00.123456Z", "2026-10-22T23:55:00.1234567Z",
    "2026-10-22T23:55:00.123456+01:00", "2026-10-22T23:55:00.123456", "invalid-private"]
    .map((accepted_at) => eta({ accepted_at })),
  eta({ ready_at: "2026-10-23T00:10:00.123455Z" }), eta({ ready_at: "2026-10-23T00:10:00.123457Z" }),
  eta({ ready_at: "2026-10-22T23:40:00.123456Z" }),
  ...[null, "", " UTC", "utc", "EST", "Factory", "localtime", "posix/Asia/Jerusalem", "right/UTC", "+01:00", "Not/AZone", "a".repeat(101)]
    .map((timezone) => eta({ timezone }))];
for (let index = 0; index < invalidEtas.length; index++) {
  test(`invalid or incomplete ETA tuple ${index + 1} fails closed without legacy downgrade`, async () => {
    const value = invalidEtas[index]; assert.equal(projectAcceptanceEta(value), null);
    const f = fixture({ upstream: success({ acceptance_eta: value }) }); const output = await f.run();
    assertNegotiated(output.response); assert.equal(output.response.status, 502); assert.equal(output.body.error, "status_unavailable");
    assert.equal(Object.hasOwn(output.body, "acceptance_eta"), false); assert.equal(f.calls.length, 1);
  });
}

for (const status of ["pending", "rejected", "expired"]) {
  test(`ETA present on ${status} is inconsistent and never projected`, async () => {
    const f = fixture({ upstream: success({ status, acceptance_eta: eta() }) }); const output = await f.run();
    assert.equal(output.response.status, 502); assertNegotiated(output.response); assert.equal(f.calls.length, 1);
  });
}

test("negotiation, ETA, capability and upstream errors never reach sensitive logs", async () => {
  const logs = []; const originals = {};
  try {
    for (const key of ["log", "warn", "error", "info", "debug"]) { originals[key] = console[key]; console[key] = (...args) => logs.push(args); }
    const f = fixture({ fetch: () => { throw new Error(`${KEY}:${TOKEN}:private-phone`); } });
    await f.run(); await f.run(statusInput(), "unsupported-private");
    const corrupt = fixture({ upstream: success({ acceptance_eta: eta({ timezone: "private-zone" }) }) }); await corrupt.run();
  } finally { for (const key of Object.keys(originals)) console[key] = originals[key]; }
  assert.deepEqual(logs, []);
});
