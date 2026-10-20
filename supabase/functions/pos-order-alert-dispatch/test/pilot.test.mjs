import test from "node:test";
import assert from "node:assert/strict";
import { webcrypto } from "node:crypto";
import { dispatchPilot } from "../../_shared/pos-order-alert-pilot.mjs";
import { createHandler } from "../handler.mjs";

const START = "2026-10-17T09:00:00Z";
const END = "2026-10-17T09:30:00Z";
const NOW = Date.parse(START);
const WORKER = "b".repeat(64);
const env = () => ({ POS_ORDER_ALERT_MODE: "pilot", POS_ORDER_ALERTS_ENABLED: "true", POS_ALERT_PILOT_START_UTC: START, POS_ALERT_PILOT_END_UTC: END,
  SUPABASE_URL: "https://synthetic.invalid", SUPABASE_SERVICE_ROLE_KEY: "synthetic-server-only", POS_ORDER_ALERT_WORKER_SECRET: WORKER,
  POS_ORDER_ALERT_FCM_SERVICE_ACCOUNT: JSON.stringify({ type: "service_account", project_id: "synthetic-project",
    client_email: "synthetic@synthetic-project.iam.gserviceaccount.com",
    private_key: ["-----BEGIN", "PRIVATE KEY-----\nSYNTHETIC"].join(" "), token_uri: "https://oauth2.googleapis.com/token" }) });
const id = (n) => `71000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
const delivery = { delivery_id: id(1), lease_id: id(2), registration_id: id(3), generation: id(4), request_id: id(5),
  kind: "pending", fcm_token: "synthetic-fcm-token-123456789", expires_at: "2026-10-17T09:10:00Z", authority_expires_at: "2026-10-17T10:00:00Z" };
const request = (auth = WORKER) => new Request("https://synthetic.invalid/functions/v1/pos-order-alert-dispatch", {
  method: "POST", headers: { Authorization: `Bearer ${auth}`, "Content-Type": "application/json" }, body: "{}",
});

for (const [label, config, nowMs] of [
  ["unset", { POS_ALERT_PILOT_START_UTC: undefined }],
  ["missing end", { POS_ALERT_PILOT_END_UTC: undefined }],
  ["offset", { POS_ALERT_PILOT_START_UTC: "2026-10-17T09:00:00+00:00" }],
  ["no timezone", { POS_ALERT_PILOT_START_UTC: "2026-10-17T09:00:00" }],
  ["invalid date", { POS_ALERT_PILOT_START_UTC: "2026-02-30T09:00:00Z" }],
  ["hour overflow", { POS_ALERT_PILOT_START_UTC: "2026-10-17T24:00:00Z" }],
  ["whitespace", { POS_ALERT_PILOT_START_UTC: ` ${START}` }],
  ["newline", { POS_ALERT_PILOT_END_UTC: `${END}\n` }],
  ["extra precision", { POS_ALERT_PILOT_START_UTC: "2026-10-17T09:00:00.0000Z" }],
  ["wrong type", { POS_ALERT_PILOT_START_UTC: NOW }],
  ["equal", { POS_ALERT_PILOT_END_UTC: START }],
  ["reversed", { POS_ALERT_PILOT_END_UTC: "2026-10-17T08:59:00Z" }],
  ["over 30 minutes", { POS_ALERT_PILOT_END_UTC: "2026-10-17T09:30:00.001Z" }],
  ["not started", {}, NOW - 1],
  ["end exclusive", {}, Date.parse(END)],
  ["invalid clock", {}, NaN],
  ["infinite clock", {}, Infinity],
  ["master OFF", { POS_ORDER_ALERTS_ENABLED: "false" }],
]) test(`dispatcher pilot ${label} denies before OAuth, claims or FCM`, async () => {
  const values = { ...env(), ...config }; let calls = 0;
  const handler = createHandler({ getEnv: (n) => values[n], cryptoImpl: webcrypto, now: () => nowMs ?? NOW,
    tokenProvider: async () => { calls++; throw new Error("unexpected OAuth"); },
    fetchImpl: async () => { calls++; throw new Error("unexpected HTTP"); } });
  assert.equal((await handler(request())).status, 503); assert.equal(calls, 0);
});

test("start is inclusive, end exclusive, exact 30 minutes valid, fractional UTC canonical", () => {
  const get = (values) => (n) => values[n];
  assert.deepEqual(dispatchPilot(get(env()), NOW), { start: NOW, end: Date.parse(END) });
  assert.ok(dispatchPilot(get(env()), Date.parse(END) - 1));
  assert.equal(dispatchPilot(get(env()), Date.parse(END)), null);
  assert.ok(dispatchPilot(get({ ...env(), POS_ALERT_PILOT_START_UTC: "2026-10-17T09:00:00.001Z" }), NOW + 1));
});

for (const auth of ["a".repeat(64), "b".repeat(63), "B".repeat(64)]) test("pilot cannot bypass worker authentication", async () => {
  const values = env(); let calls = 0;
  const handler = createHandler({ getEnv: (n) => values[n], cryptoImpl: webcrypto, now: () => NOW,
    tokenProvider: async () => { calls++; }, fetchImpl: async () => { calls++; } });
  assert.equal((await handler(request(auth))).status, 401); assert.equal(calls, 0);
});

test("expiry during OAuth prevents claiming; changed window cannot renew invocation", async () => {
  for (const invalidate of [
    (values, clock) => { clock.value = Date.parse(END); },
    (values) => { values.POS_ALERT_PILOT_END_UTC = "2026-10-17T09:29:00Z"; },
    (values) => { values.POS_ORDER_ALERTS_ENABLED = "false"; },
  ]) {
    const values = env(); const clock = { value: NOW }; let calls = 0;
    const handler = createHandler({ getEnv: (n) => values[n], cryptoImpl: webcrypto, now: () => clock.value,
      tokenProvider: async () => { invalidate(values, clock); return "synthetic-token"; },
      fetchImpl: async () => { calls++; } });
    assert.equal((await handler(request())).status, 503); assert.equal(calls, 0);
  }
});

test("expiry while claim is in flight prevents any FCM send and leaves lease untouched", async () => {
  const values = env(); let clock = NOW; const calls = [];
  const handler = createHandler({ getEnv: (n) => values[n], cryptoImpl: webcrypto, now: () => clock,
    tokenProvider: async () => "synthetic-token", fetchImpl: async (url) => {
      calls.push(url); assert.ok(url.endsWith("/pos_claim_order_alert_deliveries"));
      clock = Date.parse(END); return Response.json({ ok: true, deliveries: [delivery] });
    } });
  assert.equal((await handler(request())).status, 503); assert.equal(calls.length, 1);
});

test("finish a send that crossed cutoff, but never begin the next delivery", async () => {
  const values = env(); let clock = NOW; const calls = [];
  const handler = createHandler({ getEnv: (n) => values[n], cryptoImpl: webcrypto, now: () => clock,
    tokenProvider: async () => "synthetic-token", fetchImpl: async (url, init) => {
      calls.push({ url, init });
      if (url.endsWith("/pos_claim_order_alert_deliveries")) return Response.json({ ok: true, deliveries: [delivery, { ...delivery, delivery_id: id(6) }] });
      if (url.includes("fcm.googleapis.com")) { clock = Date.parse(END); return Response.json({ name: "projects/synthetic-project/messages/1" }); }
      assert.ok(url.endsWith("/pos_finish_order_alert_delivery"));
      assert.equal(JSON.parse(init.body).p_outcome, "sent");
      return Response.json({ ok: true });
    } });
  assert.equal((await handler(request())).status, 503);
  assert.equal(calls.filter((c) => c.url.includes("fcm.googleapis.com")).length, 1);
  assert.equal(calls.filter((c) => c.url.endsWith("/pos_finish_order_alert_delivery")).length, 1);
});
