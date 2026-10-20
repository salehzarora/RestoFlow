import test from "node:test";
import assert from "node:assert/strict";
import { webcrypto } from "node:crypto";
import { dispatchAuthority, sameDispatchAuthority } from "../../_shared/pos-order-alert-authority.mjs";
import { rpc, boundedFetch, readJson } from "../../_shared/pos-order-alert.mjs";
import { createHandler as statusHandler } from "../../pos-order-alert-status/handler.mjs";
import { createHandler as dispatchHandler } from "../handler.mjs";

const id = (n) => `71000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
const secret = "a".repeat(64);
const worker = "b".repeat(64);
const now = Date.parse("2027-10-20T09:00:00Z");
const env = () => ({ POS_ORDER_ALERTS_ENABLED: "true", SUPABASE_URL: "https://synthetic.invalid",
  SUPABASE_SERVICE_ROLE_KEY: "synthetic-only", POS_ORDER_ALERT_WORKER_SECRET: worker,
  POS_ORDER_ALERT_FCM_SERVICE_ACCOUNT: JSON.stringify({ type: "service_account", project_id: "synthetic-project",
    client_email: "synthetic@synthetic-project.iam.gserviceaccount.com", token_uri: "https://oauth2.googleapis.com/token",
    private_key: ["-----BEGIN", "PRIVATE KEY-----\nSYNTHETIC"].join(" ") }) });
const request = (path, body, bearer = secret) => new Request(`https://synthetic.invalid/functions/v1/${path}`, {
  method: "POST", headers: { Authorization: `Bearer ${bearer}`, "Content-Type": "application/json" }, body: JSON.stringify(body),
});

test("continuous authority has no restaurant/device/UTC allowlist, but master OFF and invalid mode deny", () => {
  const values = env(); const getEnv = (key) => values[key];
  const authority = dispatchAuthority(getEnv, now);
  assert.deepEqual(authority, { mode: "continuous" });
  assert.equal(sameDispatchAuthority(authority, getEnv, now + 365 * 86400000), true);
  values.POS_ORDER_ALERT_MODE = "pilot";
  assert.equal(dispatchAuthority(getEnv, now), null);
  assert.equal(sameDispatchAuthority(authority, getEnv, now), false);
  values.POS_ORDER_ALERT_MODE = "continuous";
  values.POS_ORDER_ALERTS_ENABLED = "false";
  assert.equal(dispatchAuthority(getEnv, now), null);
  for (const mode of ["", "CONTINUOUS", "true", "continuous "]) {
    assert.equal(dispatchAuthority((key) => key === "POS_ORDER_ALERT_MODE" ? mode : env()[key], now), null);
  }
  assert.equal(dispatchAuthority((key) => env()[key], NaN), null);
});

test("continuous dispatcher uses the existing max-ten lease RPC without pilot timestamps", async () => {
  const values = env(); const calls = [];
  const handler = dispatchHandler({ getEnv: (key) => values[key], cryptoImpl: webcrypto, now: () => now,
    tokenProvider: async () => "synthetic-token", fetchImpl: async (url, init) => {
      calls.push(url); assert.deepEqual(JSON.parse(init.body), { p_limit: 10 });
      return Response.json({ ok: true, deliveries: [] });
    } });
  assert.equal((await handler(request("pos-order-alert-dispatch", {}, worker))).status, 200);
  assert.equal(calls.length, 1);
  values.POS_ORDER_ALERTS_ENABLED = "false";
  assert.equal((await handler(request("pos-order-alert-dispatch", {}, worker))).status, 503);
  assert.equal(calls.length, 1);
});

test("native token refresh is status-capability bound, projects no token/PII and cannot register/renew", async () => {
  const values = env(); const calls = [];
  const expiry = "2027-10-20T10:00:00Z";
  const expected = { ok: true, registration_id: id(2), generation: id(4), server_time: "2027-10-20T09:00:00Z", authority_expires_at: expiry };
  const handler = statusHandler({ getEnv: (key) => values[key], cryptoImpl: webcrypto,
    fetchImpl: async (url, init) => { calls.push({ url, body: JSON.parse(init.body) }); return Response.json({ ...expected, fcm_token: "discard" }); } });
  const token = "synthetic-fcm-rotated-token";
  const result = await handler(request("pos-order-alert-status/token/refresh", { installation_id: id(1), fcm_token: token, generation: id(3) }));
  assert.equal(result.status, 200); assert.deepEqual(await result.json(), expected);
  assert.ok(calls[0].url.endsWith("/pos_refresh_order_alert_token"));
  assert.equal(calls[0].body.p_fcm_token, token);
  assert.equal(calls[0].body.p_expected_generation, id(3));
  assert.notEqual(calls[0].body.p_status_secret_hash, secret);
  assert.deepEqual(Object.keys(calls[0].body).sort(), ["p_expected_generation", "p_fcm_token", "p_installation_id", "p_status_secret_hash"]);
  values.POS_ORDER_ALERTS_ENABLED = "false";
  assert.equal((await handler(request("pos-order-alert-status/token/refresh", { installation_id: id(1), fcm_token: token, generation: id(3) }))).status, 503);
  assert.equal(calls.length, 1);
});

for (const input of [{ installation_id: id(1) }, { installation_id: id(1), fcm_token: "short", generation: id(3) },
  { installation_id: id(1), fcm_token: "synthetic-fcm-rotated-token" },
  { installation_id: id(1), fcm_token: "synthetic-fcm-rotated-token", generation: "bad" },
  { installation_id: id(1), fcm_token: "synthetic-fcm-rotated-token", generation: id(3), authority_expires_at: "2099-01-01T00:00:00Z" },
  { installation_id: id(1), fcm_token: "synthetic-fcm-rotated-token\n", generation: id(3) }]) {
  test("token refresh rejects incomplete, injected or malformed inputs without RPC", async () => {
    let calls = 0;
    const handler = statusHandler({ getEnv: (key) => env()[key], cryptoImpl: webcrypto,
      fetchImpl: async () => { calls++; throw new Error("network_forbidden"); } });
    assert.equal((await handler(request("pos-order-alert-status/token/refresh", input))).status, 400);
    assert.equal(calls, 0);
  });
}

for (const length of [20, 4096, 4097]) {
  test(`token refresh enforces the opaque-token length boundary ${length}`, async () => {
    let calls = 0;
    const handler = statusHandler({ getEnv: (key) => env()[key], cryptoImpl: webcrypto, fetchImpl: async () => {
      calls++;
      return Response.json({ ok: true, registration_id: id(2), generation: id(4), server_time: "2027-10-20T09:00:00Z", authority_expires_at: "2027-10-20T10:00:00Z" });
    } });
    const result = await handler(request("pos-order-alert-status/token/refresh", { installation_id: id(1), fcm_token: "a".repeat(length), generation: id(3) }));
    assert.equal(result.status, length <= 4096 ? 200 : 400);
    assert.equal(calls, length <= 4096 ? 1 : 0);
  });
}

test("RPC and FCM/OAuth JSON consumption share header/body timeout and sanitize errors", async () => {
  let signal;
  const fetchImpl = async (_url, init) => { signal = init.signal; return new Response(new ReadableStream({})); };
  await assert.rejects(rpc("synthetic", {}, { base: "https://synthetic.invalid", key: "synthetic" }, fetchImpl, 5), /upstream_timeout/);
  assert.equal(signal.aborted, true);
  await assert.rejects(boundedFetch("https://synthetic.invalid", {}, fetchImpl, 5, (result) => readJson(result)), /upstream_timeout/);
  assert.equal(signal.aborted, true);
});
