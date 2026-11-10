// Boundary (API_CONTRACT section 4.55.1): method, exact path, origin, JWT shape, media type,
// body cap, strict JSON and the exact key sets - every refusal before any RPC or provider call.
import "./no_network.mjs";
import test from "node:test";
import assert from "node:assert/strict";
import { ATTEMPT, BASE, blocked, contextOk, DEVICE, freeInput, id, JWT, later, ORDER, PIN, releaseInput, settleAll,
  startLive, startTest, statusInput, stray, TOKEN, world } from "./fixtures.mjs";

test.after(async () => { await settleAll(); assert.deepEqual(blocked, []); assert.deepEqual(stray, []); });

const nothingCalled = (w) => {
  assert.deepEqual(w.calls.rpc, []);
  assert.deepEqual(w.calls.provider, []);
  assert.deepEqual(w.calls.other, []);
};

test("transport-level refusals happen before any RPC or provider call", async () => {
  const cases = [
    [{ headers: { origin: "https://app.synthetic-product.test" } }, 403, "origin_not_allowed"],
    [{ headers: { origin: "null" } }, 403, "origin_not_allowed"],
    [{ url: `${BASE}/functions/v1/pos-card-charge?x=1` }, 404, "not_found"],
    [{ url: `${BASE}/functions/v1/pos-card-charge/extra` }, 404, "not_found"],
    [{ url: `${BASE}/functions/v1/pos-web-order-decision` }, 404, "not_found"],
    [{ method: "GET" }, 405, "method_not_allowed"],
    [{ method: "PUT" }, 405, "method_not_allowed"],
    [{ method: "OPTIONS" }, 405, "method_not_allowed"],
    [{ headers: { authorization: null } }, 401, "invalid_session"],
    [{ headers: { authorization: "Basic abc" } }, 401, "invalid_session"],
    [{ headers: { authorization: "Bearer only.two" } }, 401, "invalid_session"],
    [{ headers: { authorization: "Bearer a.b.c.d" } }, 401, "invalid_session"],
    [{ headers: { authorization: "Bearer a..c" } }, 401, "invalid_session"],
    [{ headers: { authorization: "Bearer a.b+c.d" } }, 401, "invalid_session"],
    [{ headers: { authorization: `Bearer ${"a".repeat(8200)}.b.c` } }, 401, "invalid_session"],
    [{ headers: { "content-type": "text/plain" } }, 400, "invalid_request"],
    [{ headers: { "content-type": "application/json; charset=latin1" } }, 400, "invalid_request"],
    [{ headers: { "content-encoding": "gzip" } }, 400, "invalid_request"],
  ];
  for (const [options, status, error] of cases) {
    const w = world();
    const out = await w.run(startTest(), options);
    assert.equal(out.status, status, JSON.stringify(options).slice(0, 80));
    assert.deepEqual(out.body, { ok: false, error });
    assert.match(out.headers.get("cache-control"), /no-store/);
    assert.equal(out.headers.get("access-control-allow-origin"), null);
    nothingCalled(w);
  }
});

test("the plain function path is accepted as some runtimes present it", async () => {
  const w = world({ env: { POS_CARD_PAYMENTS_ENABLED: "false" } });
  const out = await w.run(startTest(), { url: `${BASE}/pos-card-charge` });
  assert.equal(out.status, 200);
  assert.deepEqual(out.body, { ok: false, error: "card_payments_disabled" });
});

test("strict JSON: duplicate keys, trailing data, lone surrogates, BOM and oversized bodies are invalid_request", async () => {
  const valid = JSON.stringify(statusInput());
  const bodies = [
    valid.replace("{", `{"attempt_id":"${ATTEMPT}",`),
    `${valid} {}`,
    `${valid}x`,
    valid.replace("synthetic-device-session-token", "synthetic\\ud800token"),
    `\ufeff${valid}`,
    JSON.stringify({ ...statusInput(), device_session_token: "x".repeat(17 * 1024) }),
    "[]", "null", "\"start\"", "",
  ];
  for (const body of bodies) {
    const w = world();
    const out = await w.run(body);
    assert.equal(out.status, 400, body.slice(0, 60));
    assert.deepEqual(out.body, { ok: false, error: "invalid_request" });
    nothingCalled(w);
  }
});

test("exact key sets per action: any other or client-supplied key is refused before any RPC", async () => {
  const bad = [
    { ...startTest(), shift_id: id(40) },
    { ...startTest(), drawer_id: id(41) },
    { ...startTest(), employee_profile_id: id(42) },
    { ...startTest(), organization_id: id(43) },
    { ...startTest(), caller_auth_user_id: id(44) },
    { ...startTest(), p_caller_auth_user_id: id(44) },
    { ...startTest(), order_id: ORDER },
    { ...startTest(), expected_revision: 1 },
    { ...startLive(), order_id: undefined },
    { ...startLive(), expected_revision: undefined },
    (() => { const v = startTest(); delete v.attempt_id; return v; })(),
    (() => { const v = startTest(); delete v.currency_code; return v; })(),
    { ...statusInput(), mode: "test" },
    { ...statusInput(), amount_minor: 1 },
    { ...releaseInput(), source: "auto" },
    { ...freeInput(), extra: true },
    (() => { const v = freeInput(); delete v.reason; return v; })(),
    { ...statusInput(), action: "commit" },
    { ...statusInput(), action: "Start" },
    { ...statusInput(), action: "free" },
  ];
  for (const body of bad) {
    const w = world();
    const out = await w.run(body);
    assert.equal(out.status, 400, JSON.stringify(body).slice(0, 100));
    assert.deepEqual(out.body, { ok: false, error: "invalid_request" });
    nothingCalled(w);
  }
});

test("identifier forms: canonical lowercase UUIDs, a v4 attempt_id, a bounded session token", async () => {
  const bad = [
    { attempt_id: ATTEMPT.toUpperCase() },
    { attempt_id: id(10, "1") },
    { attempt_id: ATTEMPT.replace(/-/g, "") },
    { attempt_id: `{${ATTEMPT}}` },
    { attempt_id: ATTEMPT.replace("8e1e", "ce1e") },
    { attempt_id: 42 },
    { pin_session_id: PIN.toUpperCase() },
    { pin_session_id: "not-a-uuid" },
    { device_id: `${DEVICE} ` },
    { device_session_token: "" },
    { device_session_token: "   " },
    { device_session_token: "x".repeat(4097) },
    { device_session_token: `${TOKEN}\n` },
    { device_session_token: 7 },
  ];
  for (const patch of bad) {
    const w = world();
    const out = await w.run(statusInput(patch));
    assert.equal(out.status, 400, JSON.stringify(patch));
    nothingCalled(w);
  }
});

test("start schema: mode, amount token, currency and LIVE order fields", async () => {
  const bad = [
    { mode: "TEST" }, { mode: "production" }, { mode: null },
    { amount_minor: 0 }, { amount_minor: -1 }, { amount_minor: 12.34 }, { amount_minor: "1234" },
    { amount_minor: 10 ** 11 }, { amount_minor: Number.MAX_SAFE_INTEGER }, { amount_minor: null },
    { currency_code: "ils" }, { currency_code: "ILS " }, { currency_code: "IL" }, { currency_code: 376 },
  ];
  for (const patch of bad) {
    const w = world();
    const out = await w.run(startTest(patch));
    assert.equal(out.status, 400, JSON.stringify(patch));
    nothingCalled(w);
  }
  for (const body of ['"amount_minor":1234.0', '"amount_minor":1.234e3', '"amount_minor":01234', '"amount_minor":-0']) {
    const w = world();
    const out = await w.run(JSON.stringify(startTest()).replace('"amount_minor":1234', body));
    assert.equal(out.status, 400, body);
    nothingCalled(w);
  }
  for (const patch of [{ order_id: "x" }, { order_id: ORDER.toUpperCase() }, { expected_revision: -1 },
    { expected_revision: 2147483648 }, { expected_revision: 1.5 }, { expected_revision: "7" }, { expected_revision: null }]) {
    const w = world();
    const out = await w.run(startLive(patch));
    assert.equal(out.status, 400, JSON.stringify(patch));
    nothingCalled(w);
  }
});

test("status schema: source, recording_refused and refusal_code travel together", async () => {
  const bad = [
    { source: "manual" }, { source: null }, { recording_refused: "true" }, { recording_refused: true },
    { refusal_code: "conflict" }, { recording_refused: false, refusal_code: "conflict" },
    { recording_refused: true, refusal_code: "not_a_code" }, { recording_refused: true, refusal_code: "release_failed" },
  ];
  for (const patch of bad) {
    const w = world();
    const out = await w.run(statusInput(patch));
    assert.equal(out.status, 400, JSON.stringify(patch));
    nothingCalled(w);
  }
});

test("free_order schema: string fields, token source, field rules on present reason and reference", async () => {
  const bad = [
    { reason: null }, { reason: 5 }, { confirmation_reference: null }, { confirmation_source: "Provider_Report" },
    { confirmation_source: "" }, { confirmation_source: "x".repeat(33) },
    { reason: "x".repeat(201) },
    { reason: "ok\u200bok" },
    { reason: `card ${"0".repeat(12)}` },
    { reason: `${"0".repeat(4)}x${"0".repeat(4)}` },
    { confirmation_reference: "has space" },
    { confirmation_reference: "x".repeat(65) },
    { confirmation_reference: `RPT-${"0".repeat(12)}` },
  ];
  for (const patch of bad) {
    const w = world();
    const out = await w.run(freeInput(patch));
    assert.equal(out.status, 400, JSON.stringify(patch).slice(0, 80));
    assert.deepEqual(out.body, { ok: false, error: "invalid_request" });
    nothingCalled(w);
  }
});

test("a missing platform URL or anon key is unavailable after validation and before any call", async () => {
  for (const env of [{ SUPABASE_URL: undefined }, { SUPABASE_URL: "http://synthetic-project.supabase.test" },
    { SUPABASE_URL: `${BASE}/rest` }, { SUPABASE_ANON_KEY: undefined }, { SUPABASE_ANON_KEY: "short" },
    { SUPABASE_ANON_KEY: "has spaces in the synthetic key value" }]) {
    const w = world({ env });
    const out = await w.run(statusInput());
    assert.equal(out.status, 503);
    assert.deepEqual(out.body, { ok: false, error: "unavailable" });
    nothingCalled(w);
  }
});

test("a request body that stalls is refused at the read deadline (fixture 300 ms), before any RPC", async () => {
  const w = world();
  let cancelled = false;
  const body = new ReadableStream({
    start(controller) { controller.enqueue(new TextEncoder().encode('{"action":"status"')); },
    cancel() { cancelled = true; },
  });
  const started = performance.now();
  const response = await w.handler(new Request(`${BASE}/functions/v1/pos-card-charge`, { method: "POST", body, duplex: "half",
    headers: { "content-type": "application/json", authorization: `Bearer ${JWT}` } }));
  const elapsed = performance.now() - started;
  assert.equal(response.status, 400);
  assert.deepEqual(await response.json(), { ok: false, error: "invalid_request" });
  assert.ok(elapsed >= 250 && elapsed < 2_000, `answered after ${Math.round(elapsed)} ms`);
  assert.ok(cancelled, "the stalled body stream is cancelled");
  nothingCalled(w);
});

test("the byte caps bind: a padded request body and an oversized proof answer are refused before any service call", async () => {
  // A valid status request padded with JSON whitespace past 16 KiB: refused by the request cap only.
  const padded = world();
  const out = await padded.run(`${JSON.stringify(statusInput())}${" ".repeat(17 * 1024)}`);
  assert.equal(out.status, 400);
  assert.deepEqual(out.body, { ok: false, error: "invalid_request" });
  nothingCalled(padded);
  // A proof answer past the 64 KiB RPC-answer cap: unreadable, so unavailable (with the cap raised it would prove).
  const oversized = world({ rpc: { card_attempt_context: { ...contextOk(), pad: "x".repeat(70 * 1024) } } });
  const proof = await oversized.run(statusInput());
  assert.equal(proof.status, 503);
  assert.deepEqual(proof.body, { ok: false, error: "unavailable" });
  assert.deepEqual(oversized.rpcNames(), ["card_attempt_context"]);
});

test("no timer outlives a request: the body-read and RPC deadlines are cleared on every path", async () => {
  const timers = () => process.getActiveResourcesInfo().filter((name) => name === "Timeout").length;
  const before = timers();
  const refused = world({ rpc: { card_attempt_context: { ok: false, error: "permission_denied" } } });
  await refused.run(statusInput());
  assert.equal(timers(), before, "after a refused proof");
  const stalled = world();
  const stream = new ReadableStream({ start(controller) { controller.enqueue(new TextEncoder().encode('{"action":"status"')); } });
  await stalled.handler(new Request(`${BASE}/functions/v1/pos-card-charge`, { method: "POST", body: stream, duplex: "half",
    headers: { "content-type": "application/json", authorization: `Bearer ${JWT}` } }));
  assert.equal(timers(), before, "after a stalled body");
  const slow = world({ rpc: { card_attempt_context: (_body, init) => later(5_000, () => Response.json(contextOk()))(init) } });
  await slow.run(statusInput());
  assert.equal(timers(), before, "after an RPC deadline");
});
