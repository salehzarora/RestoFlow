import test from "node:test";
import assert from "node:assert/strict";
import { createHandler } from "../handler.mjs";

const id = (n) => `36600000-0000-4000-8000-${String(n).padStart(12, "0")}`;
const input = (extra = {}) => ({ action: "accept", pin_session_id: id(1), device_id: id(2),
  device_session_token: "synthetic-device", request_id: id(3), decision_id: id(4), ...extra });
const result = (extra = {}) => ({ ok: true, request_id: id(3), status: "accepted", canonical_order_id: id(5),
  decision_id: id(4), replayed: false, ...extra });
// Existing wake authority pins this destination; fetch is ALWAYS injected and
// records calls only. No request in this fixture reaches an actual network.
const BASE = "https://oqmevrndtivqxgyvcmwy.supabase.co";
function fixture({ fetch, wakeFetch, waitUntil, timeoutMs = 50, wake = true } = {}) {
  const calls = []; const tasks = []; const reads = [];
  const env = { SUPABASE_URL: BASE, SUPABASE_ANON_KEY: "synthetic-public-key",
    POS_ORDER_ALERTS_ENABLED: "true", POS_ORDER_ALERT_MODE: "continuous",
    POS_ORDER_ALERT_INSTANT_WAKE_ENABLED: wake ? "true" : "false", POS_ORDER_ALERT_WORKER_SECRET: "c".repeat(64) };
  const handler = createHandler({ getEnv: (key) => { reads.push(key); return env[key]; }, timeoutMs,
    waitUntil: (promise) => { tasks.push(promise); return waitUntil?.(promise); }, fetchImpl: async (url, init) => {
      calls.push({ url, init });
      if (url.endsWith("/pos-order-alert-dispatch")) return wakeFetch ? wakeFetch(url, init) : Response.json({ ok: true, sent: 1, deferred: 0 });
      return fetch ? fetch(url, init) : Response.json(result());
    } });
  const run = async (body = input({ preparation_minutes: 15 }), headers = {}) => {
    const response = await handler(new Request(`${BASE}/functions/v1/pos-web-order-decision`, { method: "POST",
      headers: { "content-type": "application/json", authorization: "Bearer synthetic.caller.signature", ...headers },
      body: typeof body === "string" ? body : JSON.stringify(body) }));
    return { response, body: await response.json() };
  };
  return { calls, tasks, reads, run };
}

for (const minutes of [1, 15, 240]) {
  test(`ETA accept ${minutes} uses new named RPC once with original real caller and exact six arguments`, async () => {
    const f = fixture(); const output = await f.run(input({ preparation_minutes: minutes }));
    await Promise.all(f.tasks);
    assert.deepEqual(output.body, result());
    const call = f.calls[0];
    assert.equal(call.url, `${BASE}/rest/v1/rpc/pos_accept_web_order_with_eta`);
    assert.deepEqual(JSON.parse(call.init.body), { p_pin_session_id: id(1), p_device_id: id(2),
      p_device_session_token: "synthetic-device", p_request_id: id(3), p_decision_id: id(4), p_preparation_minutes: minutes });
    assert.equal(call.init.headers.Authorization, "Bearer synthetic.caller.signature");
    assert.equal(call.init.headers.apikey, "synthetic-public-key");
    assert.equal(call.init.redirect, "error"); assert.equal(call.init.cache, "no-store");
    assert.equal(f.calls.filter((v) => v.url.includes("/rpc/")).length, 1);
    assert.equal(f.tasks.length, 1); assert.equal(f.calls.length, 2, "existing one postcommit wake remains independent");
    assert.equal(f.reads.includes("SUPABASE_SERVICE_ROLE_KEY"), false);
    assert.equal(Object.hasOwn(output.body, "acceptance_eta"), false, "POS envelope remains unchanged");
  });
}

test("absent duration preserves old five-argument accept and reject preserves customer reason route", async () => {
  for (const action of ["accept", "reject"]) {
    const f = fixture({ wake: false, fetch: async () => Response.json(action === "accept" ? result()
      : result({ status: "rejected", canonical_order_id: null })) });
    const body = input({ action, ...(action === "reject" ? { reason: "Unavailable" } : {}) });
    assert.equal((await f.run(body)).response.status, 200);
    assert.equal(f.calls[0].url, `${BASE}/rest/v1/rpc/${action === "accept" ? "pos_accept_web_order" : "pos_reject_web_order_customer"}`);
    assert.equal(Object.hasOwn(JSON.parse(f.calls[0].init.body), "p_preparation_minutes"), false);
    assert.equal(f.calls.length, 1);
  }
});

for (const duration of [null, true, false, "15", 0, -1, 241, 1.5, [], {}, 1e100]) {
  test(`malformed duration ${JSON.stringify(duration)} denies before network or wake`, async () => {
    const f = fixture(); const output = await f.run(input({ preparation_minutes: duration }));
    assert.equal(output.response.status, 400); assert.deepEqual(output.body, { ok: false, error: "invalid_request" });
    assert.equal(f.calls.length, 0); assert.equal(f.tasks.length, 0);
  });
}

test("reject forbids duration; unknown/duplicate keys and invalid authority cannot reach either route", async () => {
  for (const body of [input({ action: "reject", reason: "Unavailable", preparation_minutes: 15 }),
    input({ preparation_minutes: 15, acceptance_eta: {} })]) {
    const f = fixture(); assert.equal((await f.run(body)).response.status, 400); assert.equal(f.calls.length, 0);
  }
  const duplicate = fixture();
  const duplicateBody = JSON.stringify(input({ preparation_minutes: 15 })).replace('"preparation_minutes":15', '"preparation_minutes":15,"preparation_minutes":20');
  assert.equal((await duplicate.run(duplicateBody)).response.status, 503, "existing unreadable decision body contract stays fail closed");
  assert.equal(duplicate.calls.length, 0);
  const f = fixture(); assert.equal((await f.run(input({ preparation_minutes: 15 }), { authorization: "Bearer invalid" })).response.status, 401);
  assert.equal(f.calls.length, 0);
});

for (const error of ["invalid_session", "permission_denied", "decision_conflict", "request_expired", "ordering_unavailable"]) {
  test(`ETA ${error} preserves denial without fallback or retry`, async () => {
    const f = fixture({ fetch: async () => Response.json({ ok: false, error }) });
    assert.deepEqual((await f.run()).body, { ok: false, error });
    assert.equal(f.calls.length, 1); assert.equal(f.tasks.length, 0);
  });
}

test("ETA replay returns original winner and no duplicate terminal wake", async () => {
  const f = fixture({ fetch: async () => Response.json(result({ replayed: true })) });
  assert.deepEqual((await f.run()).body, result({ replayed: true })); assert.equal(f.calls.length, 1); assert.equal(f.tasks.length, 0);
});

for (const phase of ["headers", "body"]) {
  test(`ETA ${phase} timeout stays uncertain and never falls back or retries`, async () => {
    const f = fixture({ timeoutMs: 5, fetch: async () => phase === "headers" ? new Promise(() => {})
      : new Response(new ReadableStream({ start() {} })) });
    const output = await f.run(); assert.equal(output.response.status, 503);
    assert.deepEqual(output.body, { ok: false, error: "decision_outcome_unknown" });
    assert.equal(f.calls.length, 1); assert.equal(f.tasks.length, 0); assert.equal(f.calls[0].init.signal.aborted, true);
  });
}

test("ETA synchronous failure, invalid upstream winner and network error leak no data and never retry", async () => {
  for (const fetch of [() => { throw new Error("synthetic-secret-private-reason"); },
    async () => new Response(null, { status: 503 }), async () => Response.json(result({ decision_id: id(88) }))]) {
    const f = fixture({ fetch }); const output = await f.run();
    assert.deepEqual(output.body, { ok: false, error: "decision_outcome_unknown" });
    assert.equal(f.calls.length, 1); assert.equal(f.tasks.length, 0);
  }
});

test("ETA committed response survives synchronous handoff and asynchronous terminal-wake failures", async () => {
  for (const options of [{ waitUntil() { throw new Error("private-runtime-failure"); } },
    { wakeFetch() { throw new Error("private-network-failure"); } },
    { wakeFetch: async () => new Response(null, { status: 503 }) }]) {
    const f = fixture(options); const output = await f.run(); await Promise.all(f.tasks);
    assert.deepEqual(output.body, result()); assert.equal(output.response.status, 200);
    assert.equal(f.calls.filter((v) => v.url.includes("/rpc/")).length, 1);
    assert.equal(f.calls.filter((v) => v.url.endsWith("/pos-order-alert-dispatch")).length,
      options.waitUntil ? 0 : 1);
  }
});
