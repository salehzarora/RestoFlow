import test from "node:test";
import assert from "node:assert/strict";
import { createHash, webcrypto } from "node:crypto";
import { createHandler } from "../handler.mjs";
import { validateRequest } from "../validation.mjs";

// Deterministic synthetic credentials for offline tests only.
const AUTH = Buffer.alloc(32, 41).toString("base64url");
const STATUS = Buffer.alloc(32, 42).toString("base64url");
const WRONG = Buffer.alloc(32, 43).toString("base64url");
const ID = "cb162dcc-f390-43e6-b047-2ffac9819e1d";
const NOW = Date.parse("2026-10-14T12:05:00.000Z");
const sha = (value) => createHash("sha256").update(value).digest("hex");
const body = () => ({ action: "submit", slug: "mapsburger", request_id: ID, status_token: STATUS,
  order: { order_type: "takeaway", customer: { name: "Test only", phone: "+12025550100" },
    items: [{ menu_item_id: "fd6d9ab4-947d-45c9-a78e-7eb6dc43561c", quantity: 2, modifiers: [], notes: " Test item " }], notes: "Controlled test" } });
const permit = () => ({ slug: "mapsburger", organization_id: "11111111-1111-4111-8111-111111111111",
  restaurant_id: "22222222-2222-4222-8222-222222222222", branch_id: "33333333-3333-4333-8333-333333333333",
  request_id: ID, not_before: "2026-10-14T12:00:00.000Z", expires_at: "2026-10-14T12:10:00.000Z",
  authorization_sha256: sha(AUTH), status_token_sha256: sha(STATUS), order_sha256: sha(JSON.stringify(validateRequest(body()).order)) });
const success = (replayed = false) => ({ ok: true, request_id: ID, status: "pending", expires_at: "2026-10-14T12:20:00Z",
  totals: { currency_code: "ILS", subtotal_minor: 1000, tax_total_minor: 0, grand_total_minor: 1000 }, replayed });

function harness({ config = permit(), env = {}, auth = AUTH, clock = () => NOW, fetchImpl } = {}) {
  const calls = [];
  const values = { SUPABASE_URL: "https://synthetic.supabase.co", SUPABASE_SERVICE_ROLE_KEY: "synthetic-server-only",
    WEB_ORDERS_ENABLED: "false", WEB_ORDERS_TEST_ENABLED: "true", WEB_ORDERS_TEST_PERMIT: typeof config === "string" ? config : JSON.stringify(config), ...env };
  const handler = createHandler({ getEnv: (name) => values[name], now: clock, cryptoImpl: webcrypto,
    fetchImpl: async (url, options) => { calls.push({ url, options, args: JSON.parse(options.body) }); return fetchImpl ? fetchImpl(url, options) : Response.json(success(calls.length > 1)); } });
  const invoke = (payload = body(), headers = {}) => handler(new Request("https://edge.invalid/functions/v1/web-order-submit", {
    method: "POST", headers: { "Content-Type": "application/json", ...(auth === null ? {} : { Authorization: `Bearer ${auth}` }), ...headers }, body: JSON.stringify(payload),
  }));
  return { calls, invoke };
}

test("one protected identity uses only the service-only bounded RPC; authorization is never forwarded", async () => {
  const h = harness();
  const response = await h.invoke();
  assert.equal(response.status, 200);
  assert.equal(response.headers.get("cache-control"), "no-store, max-age=0");
  assert.equal(h.calls.length, 1);
  const call = h.calls[0];
  assert.ok(call.url.endsWith("/rpc/submit_web_order_test_request"));
  assert.equal(call.options.headers.Authorization, "Bearer synthetic-server-only");
  assert.equal(call.args.p_test_branch_id, permit().branch_id);
  assert.equal(call.args.p_test_organization_id, permit().organization_id);
  assert.equal(call.args.p_test_restaurant_id, permit().restaurant_id);
  assert.equal(call.args.p_test_request_id, ID);
  assert.equal(call.args.p_client_request_id, ID);
  assert.equal(call.args.p_test_not_before, permit().not_before);
  assert.equal(call.args.p_test_expires_at, permit().expires_at);
  assert.equal(call.args.p_status_token_hash, sha(STATUS));
  assert.equal(call.args.p_order.items[0].notes, "Test item");
  const publicText = await response.text();
  for (const privateValue of [AUTH, STATUS, "synthetic-server-only", permit().branch_id, permit().authorization_sha256]) {
    assert.ok(!publicText.includes(privateValue));
  }
  for (const privateValue of [AUTH, STATUS, permit().authorization_sha256]) assert.ok(!JSON.stringify(call).includes(privateValue));
});

for (const [name, options] of [
  ["default OFF", { env: { WEB_ORDERS_TEST_ENABLED: undefined } }],
  ["false gate", { env: { WEB_ORDERS_TEST_ENABLED: "false" } }],
  ["nonliteral gate", { env: { WEB_ORDERS_TEST_ENABLED: "TRUE" } }],
  ["conflicting general and test gates", { env: { WEB_ORDERS_ENABLED: "true" } }],
  ["missing permit", { env: { WEB_ORDERS_TEST_PERMIT: undefined } }],
  ["malformed permit", { config: "{" }], ["oversized permit", { config: " ".repeat(4097) }],
  ["missing authorization", { auth: null }], ["wrong authorization", { auth: WRONG }],
  ["malformed authorization", { auth: "not-a-256-bit-credential" }],
  ["expired", { clock: () => Date.parse(permit().expires_at) }],
  ["not yet valid", { clock: () => Date.parse(permit().not_before) - 1 }],
  ["invalid clock", { clock: () => NaN }],
]) test(`${name} denies without any database call`, async () => {
  const h = harness(options); const response = await h.invoke();
  assert.equal(response.status, 503); assert.deepEqual(await response.json(), { ok: false, error: "ordering_unavailable" });
  assert.equal(h.calls.length, 0);
});

for (const [name, mutate] of [
  ["other slug", (p) => { p.slug = "other-menu"; }],
  ["missing scope", (p) => { delete p.branch_id; }],
  ["extra config key", (p) => { p.bypass = true; }],
  ["malformed branch", (p) => { p.branch_id = "not-a-uuid"; }],
  ["nil branch", (p) => { p.branch_id = "00000000-0000-0000-0000-000000000000"; }],
  ["malformed organization", (p) => { p.organization_id = null; }],
  ["malformed restaurant", (p) => { p.restaurant_id = []; }],
  ["wrong fixed UUID", (p) => { p.request_id = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"; }],
  ["non-v4 UUID", (p) => { p.request_id = ID.replace("43e6", "13e6"); }],
  ["window too long", (p) => { p.expires_at = "2026-10-14T12:15:00.001Z"; }],
  ["window reversed", (p) => { p.expires_at = p.not_before; }],
  ["noncanonical instant", (p) => { p.not_before = "2026-10-14T12:00:00"; }],
  ["invalid instant", (p) => { p.not_before = "infinity"; }],
  ["malformed digest", (p) => { p.authorization_sha256 = "0"; }],
  ["wrong status binding", (p) => { p.status_token_sha256 = sha(WRONG); }],
  ["wrong order binding", (p) => { p.order_sha256 = sha("other"); }],
  ["shared authorization and status credential", (p) => { p.authorization_sha256 = p.status_token_sha256; }],
]) test(`${name} fails closed`, async () => {
  const p = permit(); mutate(p); const h = harness({ config: p });
  assert.equal((await h.invoke()).status, 503); assert.equal(h.calls.length, 0);
});

test("second request, changed scope slug, contact, notes, quantities or capability cannot use a valid private credential", async () => {
  for (const mutate of [
    (p) => { p.request_id = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"; }, (p) => { p.slug = "other-menu"; },
    (p) => { p.status_token = WRONG; }, (p) => { p.order.customer.phone = "+12025550101"; },
    (p) => { p.order.notes = "Changed"; }, (p) => { p.order.items[0].quantity = 3; },
  ]) {
    const payload = body(); mutate(payload); const h = harness();
    assert.equal((await h.invoke(payload)).status, 503); assert.equal(h.calls.length, 0);
  }
});

test("permit expiry during authorization denies before dispatch", async () => {
  let samples = 0; const h = harness({ clock: () => ++samples === 1 ? NOW : Date.parse(permit().expires_at) });
  assert.equal((await h.invoke()).status, 503); assert.equal(h.calls.length, 0);
});

test("same identity retry reaches durable SQL idempotency with identical arguments", async () => {
  const h = harness(); assert.equal((await (await h.invoke()).json()).replayed, false);
  assert.equal((await (await h.invoke()).json()).replayed, true);
  assert.deepEqual(h.calls[0].args, h.calls[1].args);
});

test("uncertain response does not retry writes; capability status still works after the test gate closes", async () => {
  const h = harness({ fetchImpl: async () => { throw new Error("private upstream diagnostics"); } });
  const response = await h.invoke(); assert.equal(response.status, 502);
  assert.deepEqual(await response.json(), { ok: false, error: "submission_outcome_unknown", request_id: ID, uncertain: true });
  assert.equal(h.calls.length, 1);
  const closed = harness({ env: { WEB_ORDERS_TEST_ENABLED: "false", WEB_ORDERS_TEST_PERMIT: undefined } });
  const { order: _, ...status } = body(); status.action = "status";
  assert.equal((await closed.invoke(status)).status, 200);
  assert.ok(closed.calls[0].url.endsWith("/rpc/get_web_order_request_status"));
  assert.equal(Object.keys(closed.calls[0].args).length, 3);
});

test("normal checkout uses the persistent admission RPC with the existing argument contract", async () => {
  const h = harness({ env: { WEB_ORDERS_ENABLED: "true", WEB_ORDERS_TEST_ENABLED: "false" }, auth: null });
  assert.equal((await h.invoke()).status, 200);
  assert.ok(h.calls[0].url.endsWith("/rpc/submit_web_order_platform_request"));
  assert.equal(Object.keys(h.calls[0].args).length, 4);
});

test("Origin never substitutes for private authorization and existing CORS remains exact", async () => {
  const absent = harness({ auth: null }); assert.equal((await absent.invoke(body(), { Origin: "https://menu.bizbot.systems" })).status, 503);
  const foreign = harness(); assert.equal((await foreign.invoke(body(), { Origin: "https://attacker.invalid" })).status, 403);
  assert.equal(foreign.calls.length, 0);
  const allowed = harness(); const response = await allowed.invoke(body(), { Origin: "https://menu.bizbot.systems" });
  assert.equal(response.status, 200); assert.equal(response.headers.get("access-control-allow-origin"), "https://menu.bizbot.systems");
});

test("upstream scope refusal is preserved without exposing private configuration", async () => {
  const h = harness({ fetchImpl: async () => Response.json({ ok: false, error: "ordering_unavailable" }) });
  const response = await h.invoke(); assert.equal(response.status, 503);
  assert.deepEqual(await response.json(), { ok: false, error: "ordering_unavailable" });
});
