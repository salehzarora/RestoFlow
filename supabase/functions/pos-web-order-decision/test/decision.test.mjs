import test from "node:test";
import assert from "node:assert/strict";
import { createHandler } from "../handler.mjs";

const BASE = "https://oqmevrndtivqxgyvcmwy.supabase.co";
const id = (n) => `35600000-0000-4000-8000-${String(n).padStart(12, "0")}`;
const JWT = "synthetic.caller.signature";
const ANON = "synthetic-public-anon-key";
const WORKER = "b".repeat(64);
const makeInput = (action = "accept") => ({ action, pin_session_id: id(1), device_id: id(2),
  device_session_token: "synthetic-device-secret", request_id: id(3), decision_id: id(4),
  ...(action === "reject" ? { reason: "المنتج غير متوفر" } : {}) });
const success = (input, replayed = false) => ({ ok: true, request_id: input.request_id,
  status: input.action === "accept" ? "accepted" : "rejected", canonical_order_id: input.action === "accept" ? id(5) : null,
  decision_id: input.decision_id, replayed });
function fixture({ env = {}, result, fetch, waitUntil, timeoutMs = 100, wakeTimeoutMs = 100 } = {}) {
  const calls = []; const tasks = []; const reads = [];
  const config = { SUPABASE_URL: BASE, SUPABASE_ANON_KEY: ANON,
    POS_ORDER_ALERTS_ENABLED: "true", POS_ORDER_ALERT_MODE: "continuous",
    POS_ORDER_ALERT_INSTANT_WAKE_ENABLED: "true", POS_ORDER_ALERT_WORKER_SECRET: WORKER, ...env };
  const handler = createHandler({ getEnv: (key) => { reads.push(key); return config[key]; },
    waitUntil: waitUntil ?? ((p) => tasks.push(p)), timeoutMs, wakeTimeoutMs,
    fetchImpl: async (url, init) => {
      calls.push({ url, init });
      if (fetch) return fetch(url, init);
      if (url.endsWith("/pos-order-alert-dispatch")) return Response.json({ ok: true, sent: 2, deferred: 0 });
      const input = makeInput(url.endsWith("/pos_reject_web_order_customer") ? "reject" : "accept");
      return Response.json(result ?? success(input));
    } });
  const run = async (input = makeInput(), options = {}) => {
    const headers = { "content-type": "application/json", authorization: `Bearer ${JWT}`, ...options.headers };
    const r = await handler(new Request(options.url ?? `${BASE}/functions/v1/pos-web-order-decision`, {
      method: options.method ?? "POST", headers,
      ...((options.method ?? "POST") === "POST" ? { body: typeof input === "string" ? input : JSON.stringify(input) } : {}),
    }));
    return { status: r.status, body: r.status === 204 ? null : await r.json(), headers: r.headers };
  };
  return { calls, tasks, reads, config, handler, run };
}

for (const action of ["accept", "reject"]) {
  test(`${action} forwards real caller authority and schedules one postcommit wake without a subsequent order`, async () => {
    const f = fixture(); const input = makeInput(action);
    const output = await f.run(input); await Promise.all(f.tasks);
    assert.equal(output.status, 200); assert.deepEqual(output.body, success(input));
    assert.equal(f.calls.length, 2); const decision = f.calls[0];
    assert.equal(decision.url, `${BASE}/rest/v1/rpc/${action === "accept" ? "pos_accept_web_order" : "pos_reject_web_order_customer"}`);
    assert.equal(decision.init.headers.Authorization, `Bearer ${JWT}`);
    assert.equal(decision.init.headers.apikey, ANON);
    assert.equal(decision.init.redirect, "error"); assert.equal(decision.init.cache, "no-store");
    assert.deepEqual(JSON.parse(decision.init.body), { p_pin_session_id: id(1), p_device_id: id(2),
      p_device_session_token: "synthetic-device-secret", p_request_id: id(3), p_decision_id: id(4),
      ...(action === "reject" ? { p_reason: input.reason } : {}) });
    assert.equal(f.calls[1].url, `${BASE}/functions/v1/pos-order-alert-dispatch`);
    assert.equal(f.calls[1].init.body, "{}"); assert.equal(f.calls[1].init.headers.Authorization, `Bearer ${WORKER}`);
    assert.ok(!f.reads.includes("SUPABASE_SERVICE_ROLE_KEY"));
    assert.ok(!JSON.stringify(output.body).includes("synthetic-device-secret"));
    assert.match(output.headers.get("cache-control"), /no-store/);
    assert.equal(output.headers.get("access-control-allow-origin"), null);
  });
}

for (const action of ["accept", "reject"]) {
  test(`${action} replay returns existing identity without another wake`, async () => {
    const input = makeInput(action); const f = fixture({ result: success(input, true) });
    assert.deepEqual((await f.run(input)).body, success(input, true));
    assert.equal(f.tasks.length, 0); assert.equal(f.calls.length, 1);
  });
}

for (const error of ["invalid_session", "permission_denied", "not_found", "decision_conflict", "request_expired", "shift_required", "quote_changed"]) {
  test(`business error ${error} preserves result and never wakes`, async () => {
    const f = fixture({ result: { ok: false, error, entity: "web_order_request", unsafe_extra: "do-not-expose" } });
    assert.deepEqual((await f.run()).body, { ok: false, error, entity: "web_order_request" });
    assert.equal(f.tasks.length, 0); assert.equal(f.calls.length, 1);
  });
}

test("POST, recognized origin, exact path/query, JWT and schema validation deny before network", async () => {
  for (const [input, options, status] of [
    [makeInput(), { method: "GET" }, 405], [makeInput(), { headers: { origin: "https://menu.bizbot.systems" } }, 403],
    [makeInput(), { url: `${BASE}/functions/v1/pos-web-order-decision?token=x` }, 404],
    [makeInput(), { url: `${BASE}/functions/v1/arbitrary` }, 404],
    [makeInput(), { headers: { authorization: "Bearer not-a-jwt" } }, 401],
    [makeInput(), { headers: { authorization: "" } }, 401],
    [makeInput(), { headers: { "content-type": "text/plain" } }, 400],
    [makeInput(), { headers: { "content-encoding": "gzip" } }, 400],
    [{ ...makeInput(), arbitrary: "x" }, {}, 400], [{ ...makeInput(), request_id: "bad" }, {}, 400],
    [{ ...makeInput(), action: "other" }, {}, 400], [{ ...makeInput(), reason: "not allowed on accept" }, {}, 400],
    [{ ...makeInput(), device_session_token: " " }, {}, 400], [{ ...makeInput(), device_session_token: "x".repeat(4097) }, {}, 400],
  ]) {
    const f = fixture(); assert.equal((await f.run(input, options)).status, status);
    assert.equal(f.calls.length, 0); assert.equal(f.tasks.length, 0);
  }
});

for (const origin of ["https://app.bizbot.systems", "https://resto-flow-phi.vercel.app"]) {
  test(`existing product web POS ${origin} preflight and decisions retain real JWT/PIN authority`, async () => {
    const f = fixture();
    const preflight = await f.run(undefined, { method: "OPTIONS", headers: { origin, authorization: "",
      "access-control-request-method": "POST", "access-control-request-headers": "authorization, apikey, content-type, x-client-info" } });
    assert.equal(preflight.status, 204); assert.equal(preflight.body, null);
    assert.equal(preflight.headers.get("access-control-allow-origin"), origin);
    assert.equal(preflight.headers.get("access-control-allow-methods"), "POST, OPTIONS");
    assert.equal(preflight.headers.get("access-control-allow-headers"), "authorization, apikey, content-type, x-client-info");
    assert.equal(preflight.headers.get("access-control-max-age"), "600");
    assert.equal(preflight.headers.get("access-control-allow-credentials"), null);
    assert.equal(preflight.headers.get("vary"), "Origin");
    assert.equal(f.calls.length, 0); assert.equal(f.tasks.length, 0, "OPTIONS cannot decide or wake");
    for (const action of ["accept", "reject"]) {
      const output = await f.run(makeInput(action), { headers: { origin, apikey: "untrusted-caller-key", "x-client-info": "synthetic-sdk" } });
      assert.equal(output.status, 200); assert.deepEqual(output.body, success(makeInput(action)));
      assert.equal(output.headers.get("access-control-allow-origin"), origin);
      assert.equal(output.headers.get("access-control-allow-credentials"), null);
    }
    await Promise.all(f.tasks);
    const decisionCalls = f.calls.filter((call) => call.url.includes("/rpc/")); assert.equal(decisionCalls.length, 2);
    for (const call of decisionCalls) {
      assert.equal(call.init.headers.Authorization, `Bearer ${JWT}`); assert.equal(call.init.headers.apikey, ANON);
      assert.equal(call.init.headers.origin, undefined); assert.equal(call.init.headers.cookie, undefined);
    }
  });

  test(`allowed product Origin ${origin} alone or cookies cannot authenticate; errors remain CORS-readable`, async () => {
    const noAuth = fixture();
    const denied = await noAuth.run(makeInput(), { headers: { origin, authorization: "", cookie: "session=synthetic-not-authority" } });
    assert.equal(denied.status, 401); assert.equal(denied.headers.get("access-control-allow-origin"), origin);
    assert.equal(denied.headers.get("access-control-allow-credentials"), null); assert.equal(noAuth.calls.length, 0);
    const upstreamAuth = fixture({ fetch: async () => new Response(null, { status: 401 }) });
    const invalid = await upstreamAuth.run(makeInput(), { headers: { origin } });
    assert.equal(invalid.status, 401); assert.equal(invalid.headers.get("access-control-allow-origin"), origin);
    const unavailable = fixture({ env: { SUPABASE_ANON_KEY: "" } });
    const error = await unavailable.run(makeInput(), { headers: { origin } });
    assert.equal(error.status, 503); assert.equal(error.headers.get("access-control-allow-origin"), origin);
    assert.equal(error.headers.get("access-control-allow-credentials"), null);
  });
}

test("arbitrary/null/deceptive origins and unsupported preflights never gain CORS or perform work", async () => {
  for (const origin of ["null", "https://menu.bizbot.systems", "https://attacker.test", "https://app.bizbot.systems.attacker.test",
    "https://preview-resto-flow.vercel.app", "http://app.bizbot.systems", "https://app.bizbot.systems/", "https://app.bizbot.systems:444"]) {
    for (const method of ["POST", "OPTIONS"]) {
      const f = fixture(); const denied = await f.run(makeInput(), { method, headers: { origin,
        "access-control-request-method": "POST", "access-control-request-headers": "authorization, content-type" } });
      assert.equal(denied.status, 403); assert.equal(denied.headers.get("access-control-allow-origin"), null);
      assert.equal(denied.headers.get("access-control-allow-credentials"), null); assert.equal(f.calls.length, 0); assert.equal(f.tasks.length, 0);
    }
  }
  for (const headers of [{ "access-control-request-method": "DELETE" },
    { "access-control-request-method": "POST", "access-control-request-headers": "authorization,cookie" },
    { "access-control-request-method": "POST", "access-control-request-headers": "x-admin" }, {}]) {
    const f = fixture(); const denied = await f.run(undefined, { method: "OPTIONS", headers: { origin: "https://app.bizbot.systems", ...headers } });
    assert.equal(denied.status, 403); assert.equal(f.calls.length, 0); assert.equal(f.tasks.length, 0);
  }
  const native = fixture(); assert.equal((await native.run(undefined, { method: "OPTIONS", headers: { "access-control-request-method": "POST" } })).status, 403);
});

test("public reason is trimmed, mandatory, bounded by codepoints and excludes controls", async () => {
  for (const reason of [undefined, null, "", " ", " leading", "trailing ", "\u00a0leading", "line\nbreak", "x\u007f", "\uD800", "😀".repeat(241)]) {
    const f = fixture(); assert.equal((await f.run({ ...makeInput("reject"), reason })).status, 400); assert.equal(f.calls.length, 0);
  }
  const input = { ...makeInput("reject"), reason: "😀".repeat(240) };
  const f = fixture({ result: success(input) }); assert.equal((await f.run(input)).body.ok, true);
});

test("missing/invalid configuration denies without using caller supplied apikey", async () => {
  for (const env of [{ SUPABASE_ANON_KEY: "" }, { SUPABASE_URL: "https://host/path" }, { SUPABASE_URL: "http://remote.test" },
    { SUPABASE_URL: "https://user:pass@host" }, { SUPABASE_URL: "https://host?key=x" }]) {
    const f = fixture({ env }); assert.equal((await f.run(makeInput(), { headers: { apikey: "attacker" } })).status, 503);
    assert.equal(f.calls.length, 0);
  }
});

test("REST 401/403 is invalid session; other failures remain uncertain with no retry or wake", async () => {
  for (const status of [401, 403, 404, 409, 500, 503]) {
    const f = fixture({ fetch: async () => new Response("untrusted secret-bearing upstream text", { status }) });
    const output = await f.run();
    assert.deepEqual(output.body, { ok: false, error: [401, 403].includes(status) ? "invalid_session" : "decision_outcome_unknown" });
    assert.equal(f.calls.length, 1); assert.equal(f.tasks.length, 0);
  }
});

test("malformed/mismatched terminal outcomes never authorize wake", async () => {
  for (const result of [null, [], { ok: true }, success(makeInput("reject")),
    { ...success(makeInput()), request_id: id(99) }, { ...success(makeInput()), decision_id: id(99) },
    { ...success(makeInput()), canonical_order_id: null }, { ...success(makeInput()), replayed: "false" },
    { ok: false, error: "raw_database_error" }]) {
    const f = fixture({ fetch: async () => Response.json(result) });
    assert.equal((await f.run()).body.error, "decision_outcome_unknown"); assert.equal(f.tasks.length, 0);
  }
});

test("headers and stalled response bodies share one bounded decision deadline", async () => {
  for (const fetch of [async () => new Promise(() => {}), async () => new Response(new ReadableStream({ start() {} }))]) {
    const f = fixture({ fetch, timeoutMs: 15 }); const start = Date.now();
    assert.equal((await f.run()).body.error, "decision_outcome_unknown"); assert.ok(Date.now() - start < 500);
    assert.equal(f.calls.length, 1); assert.equal(f.tasks.length, 0);
  }
});

test("notification flags, missing runtime and synchronous/asynchronous wake failures cannot change committed decision", async () => {
  for (const mode of ["off", "missing_runtime", "sync_handoff", "async_handoff", "network", "stalled_body"]) {
    const f = fixture({ env: mode === "off" ? { POS_ORDER_ALERTS_ENABLED: "false" } : {},
      waitUntil: mode === "missing_runtime" ? null : mode === "sync_handoff" ? () => { throw Error("synthetic"); }
        : mode === "async_handoff" ? () => Promise.reject(Error("synthetic")) : undefined,
      fetch: async (url) => {
        if (url.includes("/rpc/")) return Response.json({ ...success(makeInput()), ignored_secret: "never expose" });
        if (mode === "network") throw Error("synthetic transport error");
        if (mode === "stalled_body") return new Response(new ReadableStream({ start() {} }));
        return Response.json({ ok: true });
      }, wakeTimeoutMs: 15 });
    if (mode === "missing_runtime") {
      // Construct directly because fixture's nullish default intentionally supplies a recorder.
      const handler = createHandler({ getEnv: (k) => f.config[k], fetchImpl: async () => Response.json(success(makeInput())) });
      assert.equal((await handler(new Request(`${BASE}/functions/v1/pos-web-order-decision`, { method: "POST",
        headers: { authorization: `Bearer ${JWT}`, "content-type": "application/json" }, body: JSON.stringify(makeInput()) }))).status, 200);
    } else {
      assert.deepEqual((await f.run()).body, success(makeInput())); await Promise.all(f.tasks);
    }
  }
});

test("source has no sensitive logging or automatic write retry", async () => {
  const { readFile } = await import("node:fs/promises");
  const source = await readFile(new URL("../handler.mjs", import.meta.url), "utf8");
  assert.doesNotMatch(source, /console\.|SUPABASE_SERVICE_ROLE_KEY|p_retry|setInterval|while\s*\(/);
  assert.equal((source.match(/await fetchImpl\(/g) ?? []).length, 1);
});
