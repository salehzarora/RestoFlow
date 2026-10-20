import test from "node:test";
import assert from "node:assert/strict";
import { createHash, webcrypto } from "node:crypto";
import { createHandler } from "../handler.mjs";
import { validateRequest } from "../validation.mjs";
import { scheduleInstantWake } from "../instant-wake.mjs";

// All HTTP is injected. The approved destination is only compared, never contacted.
const BASE = "https://oqmevrndtivqxgyvcmwy.supabase.co";
const DISPATCH = `${BASE}/functions/v1/pos-order-alert-dispatch`;
const ID = "cb162dcc-f390-43e6-b047-2ffac9819e1d";
const STATUS = Buffer.alloc(32, 42).toString("base64url");
const AUTH = Buffer.alloc(32, 41).toString("base64url");
const WORKER = "b".repeat(64);
const NOW = Date.parse("2026-10-17T09:05:00Z");
const sha = (s) => createHash("sha256").update(s).digest("hex");
const values = () => ({ SUPABASE_URL: BASE, SUPABASE_SERVICE_ROLE_KEY: "synthetic-server-key",
  WEB_ORDERS_ENABLED: "true", POS_ORDER_ALERT_INSTANT_WAKE_ENABLED: "true", POS_ORDER_ALERTS_ENABLED: "true",
  POS_ORDER_ALERT_WORKER_SECRET: WORKER,
  POS_ALERT_PILOT_START_UTC: "2026-10-17T09:00:00Z", POS_ALERT_PILOT_END_UTC: "2026-10-17T09:30:00Z" });
const body = () => ({ action: "submit", slug: "mapsburger", request_id: ID, status_token: STATUS,
  order: { order_type: "takeaway", customer: { name: "Synthetic only", phone: "+12025550100" },
    items: [{ menu_item_id: "fd6d9ab4-947d-45c9-a78e-7eb6dc43561c", quantity: 1, modifiers: [] }], notes: "synthetic" } });
const success = (extra = {}) => ({ ok: true, request_id: ID, status: "pending", expires_at: "2026-10-17T09:20:00Z",
  totals: { currency_code: "ILS", subtotal_minor: 1000, tax_total_minor: 0, grand_total_minor: 1000 }, replayed: false, ...extra });
const request = (input) => new Request("https://edge.invalid/functions/v1/web-order-submit", {
  method: "POST", headers: { "Content-Type": "application/json", Origin: "https://menu.bizbot.systems", Authorization: `Bearer ${AUTH}` },
  body: JSON.stringify(input),
});
async function snapshot(response) {
  return { status: response.status, headers: [...response.headers], body: await response.text() };
}
function harness({ env = {}, rpc = async () => Response.json(success()), transport = async () => Response.json({ ok: true, sent: 0, deferred: 0 }),
  waitUntil, noRuntime = false, now = () => NOW, wakeTimeoutMs = 20 } = {}) {
  const configuration = { ...values(), ...env };
  const tasks = [];
  const calls = [];
  let committed = false;
  const handler = createHandler({ getEnv: (n) => configuration[n], cryptoImpl: webcrypto, now, timeoutMs: 20, wakeTimeoutMs,
    waitUntil: noRuntime ? undefined : waitUntil ?? ((task) => { tasks.push(task); }),
    fetchImpl: async (url, init) => {
      calls.push({ url, init });
      if (url.includes("/rest/v1/rpc/")) {
        const response = await rpc(url, init);
        committed = true; // Test-double commit boundary; not a database integration claim.
        return response;
      }
      assert.equal(committed, true, "no wake before the submit RPC completes");
      assert.equal(url, DISPATCH);
      return transport(url, init);
    },
  });
  return { handler, tasks, calls, configuration, wakeCalls: () => calls.filter((c) => c.url === DISPATCH) };
}

test("new committed pending Maps Burger result schedules one private bounded batch wake; response unchanged", async () => {
  const baseline = harness({ noRuntime: true });
  const h = harness();
  const expected = await snapshot(await baseline.handler(request(body())));
  assert.deepEqual(await snapshot(await h.handler(request(body()))), expected);
  assert.equal(h.tasks.length, 1);
  await Promise.all(h.tasks);
  const [{ init }] = h.wakeCalls();
  assert.equal(h.wakeCalls().length, 1);
  assert.deepEqual(init.headers, { "Content-Type": "application/json", Authorization: `Bearer ${WORKER}` });
  assert.equal(init.body, "{}"); assert.equal(init.method, "POST");
  assert.equal(init.redirect, "error"); assert.equal(init.cache, "no-store");
  assert.ok(init.signal instanceof AbortSignal);
  for (const privateValue of [STATUS, AUTH, "Synthetic only", "+12025550100", ID, "synthetic-server-key"]) {
    assert.equal(JSON.stringify(init).includes(privateValue), false);
  }
  assert.equal(expected.body.includes(WORKER), false);
});

for (const [label, change, output] of [
  ["replay", {}, success({ replayed: true })],
  ...["accepted", "rejected", "expired"].map((status) => [status, {}, success({ status })]),
  ["other tenant", { slug: "other-menu" }, success()],
  ["status read", { action: "status", order: undefined }, success()],
  ["business denial", {}, { ok: false, error: "ordering_unavailable" }],
  ["invalid result", {}, success({ replayed: undefined })],
]) test(`${label} never schedules`, async () => {
  const h = harness({ rpc: async () => Response.json(output) });
  await h.handler(request({ ...body(), ...change }));
  assert.equal(h.tasks.length, 0); assert.equal(h.wakeCalls().length, 0);
});

for (const [label, rpc] of [
  ["upstream error", async () => new Response("discard", { status: 503 })],
  ["network/unknown commit", async () => { throw new Error("synthetic private detail"); }],
  ["timeout/unknown commit", () => new Promise(() => {})],
  ["unparseable response", async () => new Response("not json")],
]) test(`${label} preserves uncertain result without wake`, async () => {
  const h = harness({ rpc }); const baseline = harness({ rpc, noRuntime: true });
  const actual = await snapshot(await h.handler(request(body())));
  assert.deepEqual(actual, await snapshot(await baseline.handler(request(body()))));
  assert.equal(JSON.parse(actual.body).uncertain, true);
  assert.equal(h.tasks.length, 0); assert.equal(h.wakeCalls().length, 0);
});

test("controlled test and manual-pilot routes do not wake even on pending success", async () => {
  const permit = { slug: "mapsburger", organization_id: "11111111-1111-4111-8111-111111111111",
    restaurant_id: "22222222-2222-4222-8222-222222222222", branch_id: "33333333-3333-4333-8333-333333333333",
    request_id: ID, not_before: "2026-10-17T09:00:00.000Z", expires_at: "2026-10-17T09:10:00.000Z",
    authorization_sha256: sha(AUTH), status_token_sha256: sha(STATUS), order_sha256: sha(JSON.stringify(validateRequest(body()).order)) };
  for (const [rpcName, env] of [
    ["submit_web_order_test_request", { WEB_ORDERS_ENABLED: "false", WEB_ORDERS_TEST_ENABLED: "true", WEB_ORDERS_TEST_PERMIT: JSON.stringify(permit) }],
    ["submit_web_order_pilot_request", { WEB_ORDERS_ENABLED: "false", WEB_ORDERS_PILOT_ENABLED: "true" }],
  ]) {
    const h = harness({ env }); const response = await h.handler(request(body()));
    assert.equal(response.status, 200); assert.ok(h.calls[0].url.endsWith(`/rpc/${rpcName}`));
    assert.equal(h.tasks.length, 0); assert.equal(h.wakeCalls().length, 0);
  }
});

for (const [label, env] of [
  ...[undefined, "false", "TRUE", "1"].map((flag) => [`instant flag ${flag}`, { POS_ORDER_ALERT_INSTANT_WAKE_ENABLED: flag }]),
  ["Edge OFF", { POS_ORDER_ALERTS_ENABLED: "false" }],
  ["missing window", { POS_ALERT_PILOT_START_UTC: undefined }],
  ["expired window", { POS_ALERT_PILOT_END_UTC: "2026-10-17T09:05:00Z" }],
  ["foreign destination", { SUPABASE_URL: "https://foreign.invalid" }],
  ["URL suffix", { SUPABASE_URL: `${BASE}/` }],
  ["missing worker", { POS_ORDER_ALERT_WORKER_SECRET: undefined }],
  ["malformed worker", { POS_ORDER_ALERT_WORKER_SECRET: `${WORKER}\n` }],
]) test(`${label} leaves checkout unchanged with zero background activity`, async () => {
  const h = harness({ env });
  assert.equal((await h.handler(request(body()))).status, 200);
  assert.equal(h.tasks.length, 0); assert.equal(h.wakeCalls().length, 0);
});

test("missing runtime and synchronous waitUntil failure perform no wake HTTP", async () => {
  for (const options of [{ noRuntime: true }, { waitUntil: () => { throw new Error("runtime unavailable"); } }]) {
    const h = harness(options);
    assert.equal((await h.handler(request(body()))).status, 200);
    await Promise.resolve(); assert.equal(h.wakeCalls().length, 0);
  }
});

for (const [label, transport] of [
  ["synchronous throw", () => { throw new Error("private output must not escape"); }],
  ["async rejection", async () => { throw new Error("private output must not escape"); }],
  ["HTTP failure", async () => new Response("private upstream output", { status: 503 })],
  ["redirect", async () => { throw new TypeError("redirect refused"); }],
]) test(`${label} cannot alter full checkout response or reject the background task`, async () => {
  const h = harness({ transport }); const baseline = harness({ noRuntime: true });
  assert.deepEqual(await snapshot(await h.handler(request(body()))), await snapshot(await baseline.handler(request(body()))));
  await Promise.all(h.tasks); assert.equal(h.wakeCalls().length, 1);
});

test("rejected injected waitUntil handoff does not leak unhandled rejection", async () => {
  const h = harness({ waitUntil: () => Promise.reject(new Error("injected handoff rejection")) });
  assert.equal((await h.handler(request(body()))).status, 200);
  await new Promise((resolve) => setImmediate(resolve));
});

for (const phase of ["headers", "body", "cancel"]) test(`deadline covers stalled ${phase} without awaiting cancellation`, async () => {
  let signal; let cancelCalled = false;
  const h = harness({ transport: (_url, init) => {
    signal = init.signal;
    if (phase === "headers") return new Promise(() => {});
    return new Response(new ReadableStream({
      start(controller) { if (phase === "cancel") controller.enqueue(new Uint8Array(4097)); },
      cancel() { cancelCalled = true; return new Promise(() => {}); },
    }));
  } });
  assert.equal((await h.handler(request(body()))).status, 200);
  // A separate test-only watchdog detects accidentally unbounded production code.
  let watchdog;
  try {
    await Promise.race([Promise.all(h.tasks), new Promise((_, reject) => {
      watchdog = setTimeout(() => reject(new Error("background task exceeded test watchdog")), 1000);
    })]);
  } finally { clearTimeout(watchdog); }
  assert.equal(signal.aborted, true);
  if (phase !== "headers") assert.equal(cancelCalled, true);
});

test("lost handoff or changed configuration before the microtask does not send", async () => {
  for (const change of [
    (c) => { c.POS_ORDER_ALERTS_ENABLED = "false"; },
    (c) => { c.POS_ALERT_PILOT_END_UTC = "2026-10-17T09:29:00Z"; },
    (c) => { c.POS_ORDER_ALERT_INSTANT_WAKE_ENABLED = "false"; },
  ]) {
    const env = values(); const tasks = []; let calls = 0;
    scheduleInstantWake({ getEnv: (n) => env[n], now: () => NOW,
      waitUntil: (task) => { tasks.push(task); change(env); }, fetchImpl: async () => { calls++; } });
    await Promise.all(tasks); assert.equal(calls, 0);
  }
});

test("late headers from an abort-ignoring transport are discarded safely", async () => {
  let complete; let cancelled = false;
  const h = harness({ transport: () => new Promise((resolve) => { complete = resolve; }) });
  await h.handler(request(body())); await Promise.all(h.tasks);
  complete(new Response(new ReadableStream({ cancel() { cancelled = true; } })));
  await new Promise((resolve) => setImmediate(resolve));
  assert.equal(cancelled, true);
});
