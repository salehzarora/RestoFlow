import test from "node:test";
import assert from "node:assert/strict";
import { webcrypto } from "node:crypto";
import { createHandler as decisionHandler } from "../handler.mjs";
import { createHandler as dispatchHandler } from "../../pos-order-alert-dispatch/handler.mjs";
import { createHandler as cronHandler, DISPATCH_URL } from "../../../../services/pos-alert-cron/lib/handler.mjs";

// Real decision, dispatcher, FCM-envelope and Cron handlers; explicit synthetic
// transaction/lease oracle only. Actual SQL locks are covered by pgTAP/race CI.
const BASE = "https://oqmevrndtivqxgyvcmwy.supabase.co";
const id = (n) => `35600000-0000-4000-8000-${String(n).padStart(12, "0")}`;
const JWT = "synthetic.caller.signature", PUBLIC = "synthetic-public", WORKER = "b".repeat(64), CRON = "c".repeat(64);
function fixture({ lostWake = false } = {}) {
  const now = () => Date.parse("2026-10-21T10:00:00Z");
  const tasks = [], sends = [], calls = []; const rows = new Map(); let status = "pending", serial = 100;
  const env = { SUPABASE_URL: BASE, SUPABASE_ANON_KEY: PUBLIC, SUPABASE_SERVICE_ROLE_KEY: "synthetic-service",
    POS_ORDER_ALERTS_ENABLED: "true", POS_ORDER_ALERT_MODE: "continuous", POS_ORDER_ALERT_INSTANT_WAKE_ENABLED: "true",
    POS_ORDER_ALERT_WORKER_SECRET: WORKER, CRON_SECRET: CRON, POS_ALERT_CRON_ENABLED: "true",
    POS_ALERT_DISPATCH_URL: DISPATCH_URL, VERCEL: "1", VERCEL_ENV: "production",
    POS_ORDER_ALERT_FCM_SERVICE_ACCOUNT: JSON.stringify({ type: "service_account", project_id: "synthetic-project",
      client_email: "synthetic@synthetic-project.iam.gserviceaccount.com", private_key: ["-----BEGIN", "PRIVATE KEY-----\nSYNTHETIC"].join(" "),
      token_uri: "https://oauth2.googleapis.com/token" }) };
  let worker;
  const fetchImpl = async (url, init) => {
    calls.push(url);
    if (url === DISPATCH_URL) {
      assert.equal(init.headers.Authorization, `Bearer ${WORKER}`); assert.equal(init.body, "{}");
      if (lostWake) throw Error("synthetic lost instant wake");
      return worker(new Request(url, init));
    }
    if (url === "https://fcm.googleapis.com/v1/projects/synthetic-project/messages:send") {
      sends.push(JSON.parse(init.body).message); return Response.json({ name: `projects/synthetic-project/messages/${sends.length}` });
    }
    const args = JSON.parse(init.body);
    if (url.endsWith("/pos_accept_web_order") || url.endsWith("/pos_reject_web_order_customer")) {
      assert.equal(init.headers.Authorization, `Bearer ${JWT}`); assert.equal(init.headers.apikey, PUBLIC);
      assert.equal(args.p_request_id, id(10)); assert.equal(status, "pending", "only one decision write is permitted");
      status = url.endsWith("/pos_accept_web_order") ? "accepted" : "rejected";
      return Response.json({ ok: true, request_id: id(10), decision_id: id(11), status,
        canonical_order_id: status === "accepted" ? id(12) : null, replayed: false });
    }
    assert.equal(init.headers.Authorization, "Bearer synthetic-service");
    if (url.endsWith("/pos_claim_order_alert_deliveries")) {
      assert.equal(args.p_limit, 10);
      if (status !== "pending") for (const device of [1, 2]) {
        if (!rows.has(device)) rows.set(device, { state: "queued", delivery_id: id(serial++), lease_id: id(serial++),
          registration_id: id(device), generation: id(20 + device), request_id: id(10), kind: "terminal",
          fcm_token: `synthetic-fcm-token-device-${device}`, expires_at: "2026-10-21T10:15:00Z",
          authority_expires_at: "2026-10-21T11:00:00Z" });
      }
      const batch = [...rows.values()].filter((row) => row.state === "queued");
      for (const row of batch) row.state = "leased";
      return Response.json({ ok: true, deliveries: batch });
    }
    if (url.endsWith("/pos_finish_order_alert_delivery")) {
      const row = [...rows.values()].find((r) => r.delivery_id === args.p_delivery_id);
      assert.equal(row.state, "leased"); assert.equal(args.p_lease_id, row.lease_id); assert.equal(args.p_outcome, "sent");
      row.state = "sent"; return Response.json({ ok: true });
    }
    throw Error("No submission, printing, payment, registration or unrelated endpoint permitted");
  };
  worker = dispatchHandler({ getEnv: (n) => env[n], fetchImpl, now, cryptoImpl: webcrypto,
    tokenProvider: async () => "synthetic-oauth-token" });
  const decide = decisionHandler({ getEnv: (n) => env[n], fetchImpl, now, waitUntil: (p) => tasks.push(p) });
  const cron = cronHandler({ getEnv: (n) => env[n], now,
    fetchImpl: async (url, init) => worker(new Request(url, init)) });
  return { tasks, sends, rows, calls,
    decide: (action) => decide(new Request(`${BASE}/functions/v1/pos-web-order-decision`, { method: "POST",
      headers: { authorization: `Bearer ${JWT}`, "content-type": "application/json" },
      body: JSON.stringify({ action, pin_session_id: id(30), device_id: id(1), device_session_token: "synthetic-device-token",
        request_id: id(10), decision_id: id(11), ...(action === "reject" ? { reason: "Public synthetic reason" } : {}) }) })),
    tick: () => cron(new Request("https://cron.invalid/api/dispatch", { headers: { authorization: `Bearer ${CRON}` } })),
    pendingSet: () => [...(status === "pending" ? [id(10)] : []), id(99)] };
}

for (const action of ["accept", "reject"]) {
  test(`${action} wakes terminal cancellation for both POS without another order; concurrent Cron shares leases`, async () => {
    const f = fixture(); assert.equal((await f.decide(action)).status, 200);
    await Promise.all([...f.tasks, f.tick()]);
    assert.equal(f.sends.length, 2); assert.equal(f.rows.size, 2);
    assert.ok(f.sends.every((message) => message.data.kind === "cancel" && message.data.request_id === id(10)));
    assert.deepEqual(f.pendingSet(), [id(99)], "full pending-set reconciliation retains another pending request");
    await f.tick(); assert.equal(f.sends.length, 2, "later Cron does not duplicate completed deliveries");
    assert.ok(f.calls.every((url) => !/submit_web_order|claim_web_order_print|begin_web_order_print|payment/.test(url)));
  });
}
test("lost terminal instant wake recovers through real Cron handler without another submission", async () => {
  const f = fixture({ lostWake: true }); await f.decide("reject"); await Promise.all(f.tasks);
  assert.equal(f.sends.length, 0); assert.equal((await f.tick()).status, 200);
  assert.equal(f.sends.length, 2); assert.deepEqual(f.pendingSet(), [id(99)]);
});
