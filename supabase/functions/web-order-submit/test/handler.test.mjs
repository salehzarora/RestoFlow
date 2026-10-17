import test from "node:test";
import assert from "node:assert/strict";
import { createHash, webcrypto } from "node:crypto";
import { createHandler } from "../handler.mjs";
import { MAX_BODY_BYTES } from "../json.mjs";

const REQUEST_ID = "cb162dcc-f390-43e6-b047-2ffac9819e1d";
const ITEM_ID = "fd6d9ab4-947d-45c9-a78e-7eb6dc43561c";
const OPTION_ID = "ebe764a3-c542-4160-a50c-536387b16ace";
// Synthetic deterministic test capability, never a real credential.
const TOKEN = Buffer.alloc(32, 17).toString("base64url");
const ORIGIN = "https://menu.bizbot.systems";
const SERVICE_KEY = "synthetic-service-role-for-offline-tests";
const BASE = "https://synthetic-project.supabase.co";

function submission() {
  return {
    action: "submit", slug: "test-menu", request_id: REQUEST_ID, status_token: TOKEN,
    order: {
      order_type: "takeaway", customer: { name: "Test Customer", phone: "+972501234567" },
      items: [{ menu_item_id: ITEM_ID, quantity: 2, modifiers: [{ modifier_option_id: OPTION_ID, quantity: 1 }] }],
      notes: "No onions\nThank you",
    },
  };
}

test("manual pilot is default OFF and routes only Maps Burger through the service-only pilot guard", async () => {
  const body = { ...submission(), slug: "mapsburger" };
  const disabled = harness({ enabled: "false" });
  assert.equal((await result(disabled.handler, body)).response.status, 503);
  assert.equal(disabled.calls.length, 0);
  const pilot = harness({ enabled: "false", env: { WEB_ORDERS_PILOT_ENABLED: "true" } });
  assert.equal((await result(pilot.handler, body)).response.status, 200);
  assert.equal(pilot.calls.length, 1);
  assert.equal(pilot.calls[0].url, `${BASE}/rest/v1/rpc/submit_web_order_pilot_request`);
  assert.equal(pilot.calls[0].args.p_slug, "mapsburger");
  assert.deepEqual(Object.keys(pilot.calls[0].args), ["p_slug", "p_client_request_id", "p_status_token_hash", "p_order"]);
  assert.equal((await result(pilot.handler, submission())).response.status, 503);
  assert.equal(pilot.calls.length, 1, "other tenants never reach admission RPC");
});

test("manual pilot propagates database closure and rejects conflicting gates", async () => {
  const body = { ...submission(), slug: "mapsburger" };
  const closed = harness({ enabled: "false", env: { WEB_ORDERS_PILOT_ENABLED: "true" },
    fetchImpl: async () => new Response(JSON.stringify({ ok: false, error: "ordering_unavailable" })) });
  assert.deepEqual((await result(closed.handler, body)).body, { ok: false, error: "ordering_unavailable" });
  for (const enabled of ["WEB_ORDERS_ENABLED", "WEB_ORDERS_TEST_ENABLED"]) {
    const conflict = harness({ enabled: "false", env: { WEB_ORDERS_PILOT_ENABLED: "true", [enabled]: "true" } });
    assert.equal((await result(conflict.handler, body)).response.status, 503);
    assert.equal(conflict.calls.length, 0);
  }
  const status = harness({ enabled: "false", env: { WEB_ORDERS_PILOT_ENABLED: "false" } });
  assert.equal((await result(status.handler, { ...body, action: "status", order: undefined })).response.status, 200);
  assert.equal(status.calls[0].url, `${BASE}/rest/v1/rpc/get_web_order_request_status`);
});

function statusRequest() {
  const { order: _order, ...body } = submission();
  return { ...body, action: "status" };
}

function success(overrides = {}) {
  return {
    ok: true, request_id: REQUEST_ID, status: "pending", expires_at: "2026-10-13T13:15:00+00:00",
    totals: { currency_code: "ILS", subtotal_minor: 2400, tax_total_minor: 432, grand_total_minor: 2832 },
    replayed: false, ...overrides,
  };
}

function request(body = submission(), options = {}) {
  const headers = { "content-type": "application/json", ...options.headers };
  return new Request("https://edge.example/functions/v1/web-order-submit", {
    method: options.method ?? "POST", headers,
    body: options.method && options.method !== "POST" ? undefined : (typeof body === "string" || body instanceof Uint8Array ? body : JSON.stringify(body)),
  });
}

function harness({ enabled = "true", env = {}, fetchImpl, timeoutMs = 10_000 } = {}) {
  const calls = [];
  const envReads = [];
  const environment = { SUPABASE_URL: BASE, SUPABASE_SERVICE_ROLE_KEY: SERVICE_KEY, WEB_ORDERS_ENABLED: enabled, ...env };
  const handler = createHandler({
    getEnv(name) { envReads.push(name); return environment[name]; },
    cryptoImpl: webcrypto, timeoutMs,
    fetchImpl: async (url, init) => {
      calls.push({ url, init, args: JSON.parse(init.body) });
      return fetchImpl ? fetchImpl(url, init) : new Response(JSON.stringify(success()));
    },
  });
  return { handler, calls, envReads };
}

async function result(handler, body = submission(), options = {}) {
  const response = await handler(request(body, options));
  return { response, body: await response.json() };
}

test("submit uses the exact RPC, only the server credential, and a SHA-256 token hash", async () => {
  const { handler, calls } = harness();
  const output = await result(handler, submission(), { headers: { origin: ORIGIN, authorization: "Bearer customer-token", apikey: "customer-apikey" } });
  assert.equal(output.response.status, 200);
  assert.deepEqual(output.body, success());
  assert.equal(output.response.headers.get("access-control-allow-origin"), ORIGIN);
  assert.match(output.response.headers.get("cache-control"), /no-store/);
  assert.equal(calls.length, 1);
  const { url, init, args } = calls[0];
  assert.equal(url, `${BASE}/rest/v1/rpc/submit_web_order_live_request`);
  assert.equal(init.method, "POST");
  assert.equal(init.redirect, "error");
  assert.equal(init.cache, "no-store");
  assert.equal(init.headers.Authorization, `Bearer ${SERVICE_KEY}`);
  assert.equal(init.headers.apikey, SERVICE_KEY);
  assert.equal(init.headers["Content-Profile"], "public");
  assert.deepEqual(Object.keys(args), ["p_slug", "p_client_request_id", "p_status_token_hash", "p_order"]);
  assert.equal(args.p_status_token_hash, createHash("sha256").update(TOKEN).digest("hex"));
  assert.equal(JSON.stringify(args).includes(TOKEN), false);
  assert.equal(JSON.stringify(output.body).includes(TOKEN), false);
  assert.equal(JSON.stringify(output.body).includes(SERVICE_KEY), false);
  assert.deepEqual(args.p_order, submission().order);
});

test("persistent Maps Burger routing admits independent customers without pilot credentials", async () => {
  const { handler, calls, envReads } = harness({
    env: { WEB_ORDERS_TEST_ENABLED: "false", WEB_ORDERS_PILOT_ENABLED: "false" },
    fetchImpl: async (_url, init) => {
      const args = JSON.parse(init.body);
      return new Response(JSON.stringify(success({ request_id: args.p_client_request_id })));
    },
  });
  const first = { ...submission(), slug: "mapsburger" };
  const second = structuredClone(first);
  second.request_id = "2c25ed67-acf7-454c-a0a5-932d6f6ea86f";
  second.status_token = Buffer.alloc(32, 18).toString("base64url");
  second.order.customer = { name: "Another Customer", phone: "+972509876543" };
  for (const body of [first, second]) {
    const output = await result(handler, body, { headers: { origin: ORIGIN } });
    assert.equal(output.response.status, 200);
    assert.equal(output.body.request_id, body.request_id);
  }
  assert.equal(calls.length, 2);
  assert.equal(calls.every((call) => call.url === `${BASE}/rest/v1/rpc/submit_web_order_live_request`), true);
  assert.notEqual(calls[0].args.p_status_token_hash, calls[1].args.p_status_token_hash);
  assert.deepEqual(calls.map((call) => call.args.p_order.customer), [first.order.customer, second.order.customer]);
  assert.equal(envReads.includes("WEB_ORDERS_TEST_PERMIT"), false);
});

test("persistent Maps Burger database OFF rejects a stale checkout while status remains usable", async () => {
  const { handler, calls } = harness({
    fetchImpl: async (url) => new Response(JSON.stringify(url.endsWith("/submit_web_order_live_request")
      ? { ok: false, error: "ordering_unavailable" }
      : success({ status: "accepted" }))),
  });
  const body = { ...submission(), slug: "mapsburger" };
  const blocked = await result(handler, body, { headers: { origin: ORIGIN } });
  assert.equal(blocked.response.status, 503);
  assert.deepEqual(blocked.body, { ok: false, error: "ordering_unavailable" });
  const { order: _order, ...status } = body;
  const existing = await result(handler, { ...status, action: "status" }, { headers: { origin: ORIGIN } });
  assert.equal(existing.response.status, 200);
  assert.equal(existing.body.status, "accepted");
  assert.equal(calls[1].url, `${BASE}/rest/v1/rpc/get_web_order_request_status`);
});

test("omitted optional fields normalize and repeated submissions keep identical RPC arguments", async () => {
  let count = 0;
  const { handler, calls } = harness({ fetchImpl: async () => new Response(JSON.stringify(success({ replayed: count++ > 0 }))) });
  const body = submission();
  body.request_id = body.request_id.toUpperCase();
  body.order.customer.name = "  Test Customer  ";
  body.order.items[0].menu_item_id = ITEM_ID.toUpperCase();
  delete body.order.notes;
  delete body.order.items[0].modifiers;
  assert.equal((await result(handler, body)).body.replayed, false);
  assert.equal((await result(handler, body)).body.replayed, true);
  assert.deepEqual(calls[0].args, calls[1].args);
  assert.equal(calls[0].args.p_client_request_id, REQUEST_ID);
  assert.deepEqual(calls[0].args.p_order, {
    order_type: "takeaway", customer: { name: "Test Customer", phone: "+972501234567" },
    items: [{ menu_item_id: ITEM_ID, quantity: 2, modifiers: [] }], notes: "",
  });
});

test("item notes remain per-line and independent of order notes through exact retries", async () => {
  const { handler, calls } = harness();
  const body = submission();
  body.order.items[0].notes = " \u00a0بدون بصل\nבלי בצל 🍽\u3000 ";
  body.order.items.push({ ...body.order.items[0], notes: "Extra onion" });
  await result(handler, body);
  await result(handler, body);
  assert.deepEqual(calls[0].args, calls[1].args);
  assert.equal(calls[0].args.p_order.items.length, 2);
  assert.equal(calls[0].args.p_order.items[0].notes, "بدون بصل\nבלי בצל 🍽");
  assert.equal(calls[0].args.p_order.items[1].notes, "Extra onion");
  assert.equal(calls[0].args.p_order.notes, body.order.notes);
  assert.deepEqual(calls[0].args.p_order.items[0].modifiers, body.order.items[0].modifiers);
});

test("absent and empty item notes preserve the old note-free normalized identity", async () => {
  const { handler, calls } = harness();
  for (const notes of [undefined, "", " \n\u00a0\u3000 "]) {
    const body = submission();
    if (notes !== undefined) body.order.items[0].notes = notes;
    assert.equal((await result(handler, body)).response.status, 200);
  }
  assert.deepEqual(calls[0].args, calls[1].args);
  assert.deepEqual(calls[0].args, calls[2].args);
  assert.equal(Object.hasOwn(calls[0].args.p_order.items[0], "notes"), false);
});

test("item notes count Unicode scalars and reject invalid or oversized raw input without truncation", async () => {
  const { handler, calls } = harness();
  for (const notes of [null, 1, false, [], {}, "a".repeat(141), "🍽".repeat(141), " ".repeat(141), "a\tb", "a\rb", "a\0b", "a\u007fb", "a\u0085b", "a\u009fb", "a\ud800b", "a\udfffb"]) {
    const body = submission();
    body.order.items[0].notes = notes;
    const output = await result(handler, body);
    assert.equal(output.response.status, 400, JSON.stringify(notes));
    assert.deepEqual(output.body, { ok: false, error: "invalid_request" });
  }
  assert.equal(calls.length, 0);
  const body = submission();
  body.order.items[0].notes = "🍽".repeat(140);
  assert.equal((await result(handler, body)).response.status, 200);
  assert.equal(calls[0].args.p_order.items[0].notes, body.order.items[0].notes);
  const duplicate = JSON.stringify(submission()).replace('"quantity":2,', '"quantity":2,"notes":"one","notes":"two",');
  assert.equal((await result(handler, duplicate)).response.status, 400);
});

test("default and non-exact submit gates stop before reading server credentials or fetching", async () => {
  for (const enabled of [undefined, "false", "TRUE", "1", "true ", ""]) {
    const { handler, calls, envReads } = harness({ env: { WEB_ORDERS_ENABLED: enabled } });
    const output = await result(handler);
    assert.equal(output.response.status, 503);
    assert.deepEqual(output.body, { ok: false, error: "ordering_unavailable" });
    assert.equal(calls.length, 0);
    assert.equal(envReads.includes("SUPABASE_SERVICE_ROLE_KEY"), false);
    assert.equal(envReads.includes("SUPABASE_URL"), false);
  }
});

test("status stays available with submit disabled and sends only capability lookup arguments", async () => {
  const { handler, calls } = harness({ enabled: "false", fetchImpl: async () => new Response(JSON.stringify(success({ status: "expired" }))) });
  const output = await result(handler, statusRequest());
  assert.equal(output.response.status, 200);
  assert.equal(output.body.status, "expired");
  assert.equal(calls.length, 1);
  assert.equal(calls[0].url, `${BASE}/rest/v1/rpc/get_web_order_request_status`);
  assert.deepEqual(Object.keys(calls[0].args), ["p_slug", "p_client_request_id", "p_status_token_hash"]);
});

test("no Origin permits server calls; configured origins match exactly", async () => {
  const custom = "https://preview.example";
  const { handler, calls } = harness({ env: { WEB_ORDERS_ALLOWED_ORIGIN: custom } });
  assert.equal((await result(handler)).response.status, 200);
  const allowed = await result(handler, submission(), { headers: { origin: custom } });
  assert.equal(allowed.response.headers.get("access-control-allow-origin"), custom);
  for (const origin of [ORIGIN, `${custom}/`, "https://preview.example.evil.test", "null", ""]) {
    const output = await result(handler, submission(), { headers: { origin } });
    assert.equal(output.response.status, 403);
    assert.equal(output.response.headers.has("access-control-allow-origin"), false);
  }
  assert.equal(calls.length, 2);
});

test("preflight is fixed to supported headers and POST; methods cannot invoke an RPC", async () => {
  const { handler, calls } = harness();
  const preflight = await handler(request(undefined, { method: "OPTIONS", headers: { origin: ORIGIN, "access-control-request-method": "POST", "access-control-request-headers": "content-type, authorization, apikey, x-client-info" } }));
  assert.equal(preflight.status, 204);
  assert.equal(await preflight.text(), "");
  assert.equal(preflight.headers.get("access-control-allow-origin"), ORIGIN);
  assert.equal(preflight.headers.has("access-control-allow-credentials"), false);
  for (const headers of [{ "access-control-request-method": "PUT" }, { "access-control-request-headers": "x-service-role" }]) {
    assert.equal((await handler(request(undefined, { method: "OPTIONS", headers: { origin: ORIGIN, ...headers } }))).status, 403);
  }
  for (const method of ["GET", "PUT", "DELETE", "PATCH"]) {
    const output = await result(handler, undefined, { method });
    assert.equal(output.response.status, 405);
    assert.equal(output.response.headers.get("allow"), "POST, OPTIONS");
  }
  assert.equal(calls.length, 0);
});

test("unknown fields and authority or price injections fail at every object boundary", async () => {
  const mutations = [
    (body) => { body.tenant_id = ITEM_ID; },
    (body) => { body.branch_id = ITEM_ID; },
    (body) => { body.totals = { grand_total_minor: 0 }; },
    (body) => { body.order.price = 0; },
    (body) => { body.order.currency_code = "USD"; },
    (body) => { body.order.tax = 0; },
    (body) => { body.order.customer.organization_id = ITEM_ID; },
    (body) => { body.order.items[0].unit_price_minor = 0; },
    (body) => { body.order.items[0].modifiers[0].price = 0; },
    (body) => { body.order.items[0].modifiers[0].tenant = { id: ITEM_ID }; },
    (body) => { body.order.customer.name = { value: "Customer", branch_id: ITEM_ID }; },
  ];
  for (const mutate of mutations) {
    const { handler, calls } = harness();
    const body = submission();
    mutate(body);
    const output = await result(handler, body);
    assert.equal(output.response.status, 400);
    assert.deepEqual(output.body, { ok: false, error: "invalid_request" });
    assert.equal(calls.length, 0);
  }
  const { handler, calls } = harness();
  assert.equal((await result(handler, { ...statusRequest(), order: submission().order })).response.status, 400);
  assert.equal(calls.length, 0);
});

test("required fields, exact primitives and container types are enforced", async () => {
  const mutations = [
    (b) => { delete b.action; }, (b) => { delete b.slug; }, (b) => { delete b.request_id; },
    (b) => { delete b.status_token; }, (b) => { delete b.order; },
    (b) => { b.action = "accept"; }, (b) => { b.order = null; },
    (b) => { b.order.customer = []; }, (b) => { delete b.order.customer.phone; },
    (b) => { b.order.customer.name = 12; }, (b) => { b.order.customer.phone = 972501234567; },
    (b) => { b.order.notes = null; }, (b) => { b.order.items = {}; },
    (b) => { b.order.items[0] = null; }, (b) => { delete b.order.items[0].quantity; },
    (b) => { b.order.items[0].modifiers = null; }, (b) => { b.order.items[0].modifiers[0] = []; },
    (b) => { delete b.order.items[0].modifiers[0].modifier_option_id; },
  ];
  const { handler, calls } = harness();
  for (const mutate of mutations) {
    const body = submission(); mutate(body);
    assert.equal((await result(handler, body)).response.status, 400);
  }
  for (const body of [null, [], true, 1, "null"]) assert.equal((await result(handler, body)).response.status, 400);
  assert.equal(calls.length, 0);
});

test("slug storage grammar, UUIDv4 and canonical 32-byte capabilities are required", async () => {
  const { handler, calls } = harness();
  for (const slug of ["ab", "x".repeat(49), "UPPER", "a--b", "-abc", "abc-", "a_b", "a/b", " café "]) {
    assert.equal((await result(handler, { ...submission(), slug })).response.status, 400);
  }
  for (const request_id of [ITEM_ID.replace("45c9", "35c9"), REQUEST_ID.replace("b047", "7047"), `{${REQUEST_ID}}`, REQUEST_ID.replaceAll("-", ""), null]) {
    assert.equal((await result(handler, { ...submission(), request_id })).response.status, 400);
  }
  for (const status_token of [TOKEN + "=", TOKEN.slice(1), TOKEN.slice(0, 42) + "B", "+" + TOKEN.slice(1), Buffer.alloc(31).toString("base64url"), Buffer.alloc(33).toString("base64url"), null]) {
    assert.equal((await result(handler, { ...submission(), status_token })).response.status, 400);
  }
  assert.equal(calls.length, 0);
  for (const slug of ["abc", "a-1", "a".repeat(48)]) assert.equal((await result(handler, { ...submission(), slug })).response.status, 200);
});

test("only takeaway, trimmed names, E.164 phones and bounded non-control notes are accepted", async () => {
  const { handler, calls } = harness();
  const invalidChanges = [
    (b) => { b.order.order_type = "delivery"; },
    (b) => { b.order.customer.name = " \n "; },
    (b) => { b.order.customer.name = "n".repeat(81); },
    (b) => { b.order.customer.name = "Customer\u0000"; },
    (b) => { b.order.customer.name = "Customer\u0085Name"; },
    (b) => { b.order.customer.name = "\ud800"; },
    (b) => { b.order.notes = "n".repeat(501); },
    (b) => { b.order.notes = "a\tb"; },
    (b) => { b.order.notes = "a\rb"; },
    (b) => { b.order.notes = "\u0000"; },
    (b) => { b.order.notes = "\udfff"; },
  ];
  for (const mutate of invalidChanges) { const body = submission(); mutate(body); assert.equal((await result(handler, body)).response.status, 400); }
  for (const phone of ["0501234567", "+012345678", "+1234567", "+1234567890123456", "+972 501234567", "+972-501234567"]) {
    const body = submission(); body.order.customer.phone = phone;
    assert.equal((await result(handler, body)).response.status, 400);
  }
  assert.equal(calls.length, 0);
  const boundary = submission();
  boundary.order.customer.name = "😀".repeat(80);
  boundary.order.customer.phone = "+12345678";
  boundary.order.notes = "n".repeat(499) + "\n";
  assert.equal((await result(handler, boundary)).response.status, 200);
});

test("item and modifier caps, integer quantities, UUIDs and per-line duplicate selections are enforced", async () => {
  const { handler, calls } = harness();
  const mutations = [
    (b) => { b.order.items = []; },
    (b) => { b.order.items = Array.from({ length: 21 }, () => ({ menu_item_id: ITEM_ID, quantity: 1 })); },
    (b) => { b.order.items = Array.from({ length: 3 }, () => ({ menu_item_id: ITEM_ID, quantity: 20 })); },
    (b) => { b.order.items[0].menu_item_id = "not-a-uuid"; },
    (b) => { b.order.items[0].modifiers = Array.from({ length: 21 }, () => ({ modifier_option_id: OPTION_ID, quantity: 1 })); },
    (b) => { b.order.items[0].modifiers.push({ modifier_option_id: OPTION_ID.toUpperCase(), quantity: 1 }); },
    (b) => { b.order.items[0].modifiers[0].modifier_option_id = "invalid"; },
  ];
  for (const mutate of mutations) { const body = submission(); mutate(body); assert.equal((await result(handler, body)).response.status, 400); }
  for (const quantity of [0, -1, 21, 1.5, "2", null, true]) {
    const itemBody = submission(); itemBody.order.items[0].quantity = quantity;
    const modifierBody = submission(); modifierBody.order.items[0].modifiers[0].quantity = quantity;
    assert.equal((await result(handler, itemBody)).response.status, 400);
    assert.equal((await result(handler, modifierBody)).response.status, 400);
  }
  assert.equal(calls.length, 0);
  const boundary = submission();
  boundary.order.items = [20, 20, 10].map((quantity) => ({ menu_item_id: ITEM_ID, quantity, modifiers: [] }));
  assert.equal((await result(handler, boundary)).response.status, 200);
});

test("duplicate JSON keys are rejected at all depths, including escaped and prototype keys", async () => {
  const body = JSON.stringify(submission());
  const duplicates = [
    body.replace('"action":"submit"', '"action":"submit","action":"status"'),
    body.replace('"slug":"test-menu"', '"slug":"test-menu","sl\\u0075g":"other-menu"'),
    body.replace('"order_type":"takeaway"', '"order_type":"takeaway","order_type":"takeaway"'),
    body.replace('"name":"Test Customer"', '"name":"Test Customer","name":"Other Customer"'),
    body.replace(`"menu_item_id":"${ITEM_ID}"`, `"menu_item_id":"${ITEM_ID}","menu_item_id":"${ITEM_ID}"`),
    body.replace(`"modifier_option_id":"${OPTION_ID}"`, `"modifier_option_id":"${OPTION_ID}","modifier_option_id":"${OPTION_ID}"`),
    '{"__proto__":1,"__proto__":2}',
  ];
  const { handler, calls } = harness();
  for (const duplicate of duplicates) {
    const output = await result(handler, duplicate);
    assert.equal(output.response.status, 400);
    assert.deepEqual(output.body, { ok: false, error: "invalid_json" });
  }
  assert.equal((await result(handler, body.replace('"action":"submit"', '"__proto__":{},"action":"submit"'))).response.status, 400);
  assert.equal({}.polluted, undefined);
  assert.equal(calls.length, 0);
});

test("malformed JSON, invalid UTF-8, BOMs and excessive nesting fail before an RPC", async () => {
  const { handler, calls } = harness();
  for (const body of ["", "{", '{"x":01}', '{"x":NaN}', '{"x":1e999}', '{"x":1,}', '[1,]', "{} garbage", '\ufeff' + JSON.stringify(submission()), "[".repeat(34) + "0" + "]".repeat(34), new Uint8Array([0x7b, 0x22, 0xc3, 0x28, 0x22, 0x3a, 0x31, 0x7d])]) {
    const output = await result(handler, body);
    assert.equal(output.response.status, 400);
    assert.equal(output.body.error, "invalid_json");
  }
  assert.equal(calls.length, 0);
});

test("media types and content encodings are explicit", async () => {
  const { handler, calls } = harness();
  for (const type of ["text/plain", "application/json; charset=latin1", "application/jsonp", "application/json; extra=1", ""]) {
    assert.equal((await result(handler, submission(), { headers: { "content-type": type } })).response.status, 415);
  }
  assert.equal((await result(handler, submission(), { headers: { "content-encoding": "gzip" } })).response.status, 415);
  assert.equal(calls.length, 0);
  assert.equal((await result(handler, submission(), { headers: { "content-type": 'Application/JSON; charset="UTF-8"', "content-encoding": "identity" } })).response.status, 200);
});

test("32 KiB cap counts streamed bytes and cancels input even when Content-Length lies", async () => {
  const { handler, calls } = harness();
  assert.equal((await result(handler, submission(), { headers: { "content-length": String(MAX_BODY_BYTES + 1) } })).response.status, 413);
  let canceled = false;
  const stream = new ReadableStream({
    start(controller) { controller.enqueue(new Uint8Array(16_384)); controller.enqueue(new Uint8Array(16_385)); },
    cancel() { canceled = true; },
  });
  const output = await handler(new Request("https://edge.example", { method: "POST", headers: { "content-type": "application/json", "content-length": "1" }, body: stream, duplex: "half" }));
  assert.equal(output.status, 413);
  assert.equal(canceled, true);
  assert.equal(calls.length, 0);
  const encoded = JSON.stringify(submission());
  const exactLimit = encoded + " ".repeat(MAX_BODY_BYTES - Buffer.byteLength(encoded));
  assert.equal((await result(handler, exactLimit)).response.status, 200);
  assert.equal((await result(handler, exactLimit + " ")).response.status, 413);
  assert.equal(calls.length, 1);
  const multibyte = submission(); multibyte.order.notes = "😀".repeat(500);
  const text = JSON.stringify(multibyte);
  const byteOverLimit = text + " ".repeat(MAX_BODY_BYTES - text.length);
  assert.equal((await result(handler, byteOverLimit)).response.status, 413);
  assert.equal(calls.length, 1);
});

test("business failures are typed and capability failure looks the same as unknown request", async () => {
  const cases = [
    ["invalid_request", 400], ["not_found", 404], ["ordering_unavailable", 503], ["idempotency_conflict", 409],
    ["item_unavailable", 422], ["modifier_selection_invalid", 422], ["menu_unavailable", 422], ["rate_limited", 429], ["capacity_reached", 429],
  ];
  for (const [error, status] of cases) {
    const { handler } = harness({ fetchImpl: async () => new Response(JSON.stringify({ ok: false, error })) });
    const output = await result(handler);
    assert.equal(output.response.status, status);
    assert.deepEqual(output.body, { ok: false, error });
  }
  const { handler, calls } = harness({ fetchImpl: async () => new Response(JSON.stringify({ ok: false, error: "not_found" })) });
  const wrongCapability = { ...statusRequest(), status_token: Buffer.alloc(32, 22).toString("base64url") };
  const wrongRequest = { ...statusRequest(), request_id: "7d726639-ea4f-4e47-9dbd-ff14004eb042" };
  const wrongSlug = { ...statusRequest(), slug: "other-restaurant" };
  const outputs = await Promise.all([wrongCapability, wrongRequest, wrongSlug].map((body) => result(handler, body)));
  assert.deepEqual(outputs.map(({ body }) => body), Array(3).fill({ ok: false, error: "not_found" }));
  assert.equal(calls.length, 3);
});

test("public results project no PII, SQL diagnostics, secret fields or raw capabilities", async () => {
  const secretResult = success({
    customer: { name: "Sensitive Test", phone: "+972599999999" }, status_token: TOKEN,
    status_token_hash: "hash-must-stay-internal", service_role_key: SERVICE_KEY,
    notes: "private notes", tenant_id: ITEM_ID, internal_order_id: OPTION_ID,
  });
  secretResult.totals.internal_cost_minor = 123;
  const { handler } = harness({ fetchImpl: async () => new Response(JSON.stringify(secretResult)) });
  const output = await result(handler, statusRequest());
  assert.deepEqual(output.body, success());
  const business = harness({ fetchImpl: async () => new Response(JSON.stringify({ ok: false, error: "not_found", detail: TOKEN, customer: secretResult.customer, key: SERVICE_KEY })) });
  assert.deepEqual((await result(business.handler, statusRequest())).body, { ok: false, error: "not_found" });
});

test("transport loss never retries or generates another request ID, even when a commit may have happened", async () => {
  let committed = false;
  const { handler, calls } = harness({ fetchImpl: async () => {
    if (!committed) { committed = true; throw new Error(`synthetic transport lost ${TOKEN} ${SERVICE_KEY}`); }
    return new Response(JSON.stringify(success({ replayed: true })));
  } });
  const first = await result(handler);
  assert.equal(first.response.status, 502);
  assert.deepEqual(first.body, { ok: false, error: "submission_outcome_unknown", request_id: REQUEST_ID, uncertain: true });
  assert.equal(calls.length, 1);
  const second = await result(handler);
  assert.equal(second.response.status, 200);
  assert.equal(second.body.replayed, true);
  assert.equal(calls.length, 2);
  assert.deepEqual(calls[0].args, calls[1].args);
});

test("timeout aborts a single submission and reports an uncertain 503 outcome", async () => {
  let signal;
  const { handler, calls } = harness({ timeoutMs: 5, fetchImpl: (_url, init) => { signal = init.signal; return new Promise(() => {}); } });
  const output = await result(handler);
  assert.equal(output.response.status, 503);
  assert.deepEqual(output.body, { ok: false, error: "submission_outcome_unknown", request_id: REQUEST_ID, uncertain: true });
  assert.equal(calls.length, 1);
  assert.equal(signal.aborted, true);
});

test("non-success HTTP responses are opaque and status transport failures cannot disclose request existence", async () => {
  for (const [status, expected] of [[301, 502], [400, 502], [401, 502], [403, 502], [429, 503], [500, 502], [503, 503], [504, 503]]) {
    const { handler, calls } = harness({ fetchImpl: async () => new Response(`private SQL ${TOKEN} ${SERVICE_KEY}`, { status, headers: { location: "https://other.example" } }) });
    const output = await result(handler);
    assert.equal(output.response.status, expected);
    assert.deepEqual(output.body, { ok: false, error: "submission_outcome_unknown", request_id: REQUEST_ID, uncertain: true });
    assert.equal(calls.length, 1);
  }
  const { handler, calls } = harness({ fetchImpl: async () => { throw new Error(`SQL ${TOKEN}`); } });
  const output = await result(handler, statusRequest());
  assert.equal(output.response.status, 502);
  assert.deepEqual(output.body, { ok: false, error: "status_unavailable", request_id: REQUEST_ID, uncertain: false });
  assert.equal(calls.length, 1);
});

test("malformed, oversized or invalid database results cannot be treated as definitive submission failures", async () => {
  const badResults = [
    "not JSON", JSON.stringify({ ok: false, error: `private ${TOKEN}` }),
    JSON.stringify(success({ request_id: ITEM_ID })), JSON.stringify(success({ status: "paid" })),
    JSON.stringify(success({ expires_at: "private" })), JSON.stringify(success({ replayed: "true" })),
    JSON.stringify(success({ totals: { currency_code: "USD", subtotal_minor: 1, tax_total_minor: 0, grand_total_minor: 1 } })),
    JSON.stringify(success({ totals: { currency_code: "ILS", subtotal_minor: 1, tax_total_minor: 0, grand_total_minor: 2 } })),
    JSON.stringify(success({ totals: { currency_code: "ILS", subtotal_minor: 10_000_001, tax_total_minor: 0, grand_total_minor: 10_000_001 } })),
    JSON.stringify(success({ totals: { currency_code: "ILS", subtotal_minor: -1, tax_total_minor: 0, grand_total_minor: -1 } })),
    JSON.stringify(success()).replace('"ok":true', '"ok":false,"ok":true'),
    "x".repeat(MAX_BODY_BYTES + 1),
  ];
  for (const body of badResults) {
    const { handler, calls } = harness({ fetchImpl: async () => new Response(body) });
    const output = await result(handler);
    assert.equal(output.response.status, 502);
    assert.deepEqual(output.body, { ok: false, error: "submission_outcome_unknown", request_id: REQUEST_ID, uncertain: true });
    assert.equal(calls.length, 1);
  }
});

test("missing or invalid server configuration fails closed without fetch or secret disclosure", async () => {
  for (const env of [
    { SUPABASE_URL: undefined }, { SUPABASE_SERVICE_ROLE_KEY: undefined },
    { SUPABASE_URL: "not-a-url" }, { SUPABASE_URL: "http://external.example" },
    { SUPABASE_URL: "https://user:password@external.example" },
    { SUPABASE_URL: `${BASE}/rest/v1` }, { SUPABASE_URL: `${BASE}?secret=example` },
  ]) {
    const { handler, calls } = harness({ env });
    const output = await result(handler);
    assert.equal(output.response.status, 503);
    assert.deepEqual(output.body, { ok: false, error: "ordering_unavailable", uncertain: false });
    assert.equal(calls.length, 0);
  }
  const { handler, calls } = harness({ env: { SUPABASE_URL: "http://127.0.0.1:54321" } });
  assert.equal((await result(handler)).response.status, 200);
  assert.equal(calls[0].url, "http://127.0.0.1:54321/rest/v1/rpc/submit_web_order_live_request");
});

test("Supabase's exact injected local gateway is allowed while other HTTP network targets stay denied", async () => {
  for (const base of ["http://kong:8000", "http://kong:8000/"]) {
    const { handler, calls } = harness({ env: { SUPABASE_URL: base } });
    assert.equal((await result(handler)).response.status, 200);
    assert.equal(calls.length, 1);
    assert.equal(calls[0].url, "http://kong:8000/rest/v1/rpc/submit_web_order_live_request");
    assert.equal(calls[0].init.headers.Authorization, `Bearer ${SERVICE_KEY}`);
  }
  for (const base of [
    "http://kong", "http://kong:8001", "http://kong.example:8000", "http://other:8000",
    "http://192.168.1.2:8000", "http://10.0.0.1:8000",
    "http://user:password@kong:8000", "http://kong:8000/rest/v1",
    "http://kong:8000?redirect=example", "http://kong:8000#fragment",
  ]) {
    const { handler, calls } = harness({ env: { SUPABASE_URL: base } });
    const output = await result(handler);
    assert.equal(output.response.status, 503);
    assert.deepEqual(output.body, { ok: false, error: "ordering_unavailable", uncertain: false });
    assert.equal(calls.length, 0);
  }
});
