import test from "node:test";
import assert from "node:assert/strict";
import { webcrypto } from "node:crypto";
import { createHandler as submissionHandler } from "../../web-order-submit/handler.mjs";
import { createHandler as dispatchHandler } from "../handler.mjs";
import { createHandler as cronHandler, DISPATCH_URL } from "../../../../services/pos-alert-cron/lib/handler.mjs";

// Contract simulation only: real handlers/FCM payloads against an explicit shared
// lease oracle. This does not execute or prove PostgreSQL SKIP LOCKED semantics.
const WORKER = "b".repeat(64);
const CRON = "a".repeat(64);
const START = "2026-10-17T09:00:00Z";
const END = "2026-10-17T09:30:00Z";
const id = (n) => `71000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
const clientId = "cb162dcc-f390-43e6-b047-2ffac9819e1d";
const makeRequest = () => ({ action: "submit", slug: "mapsburger", request_id: clientId,
  status_token: Buffer.alloc(32, 42).toString("base64url"), order: { order_type: "takeaway",
    customer: { name: "Synthetic only", phone: "+12025550100" },
    items: [{ menu_item_id: id(99), quantity: 1, modifiers: [] }] } });
const post = (url, body, auth) => new Request(url, { method: "POST", headers: {
  "Content-Type": "application/json", ...(auth ? { Authorization: `Bearer ${auth}` } : {}),
}, body: JSON.stringify(body) });

function fixture({ dropWake = false, fcmStatus = 200, enabled = true } = {}) {
  let clock = Date.parse(START) + 1000;
  let serial = 100;
  let operator = enabled;
  let registered = enabled;
  let failNextFinish = false;
  const requests = new Map(); const rows = new Map();
  const calls = []; const sends = []; const tasks = [];
  const env = { SUPABASE_URL: "https://oqmevrndtivqxgyvcmwy.supabase.co", SUPABASE_SERVICE_ROLE_KEY: "synthetic-server-key",
    POS_ORDER_ALERT_WORKER_SECRET: WORKER, POS_ORDER_ALERT_MODE: "pilot", POS_ORDER_ALERTS_ENABLED: "true", POS_ORDER_ALERT_INSTANT_WAKE_ENABLED: "true",
    POS_ALERT_PILOT_START_UTC: START, POS_ALERT_PILOT_END_UTC: END, WEB_ORDERS_ENABLED: "true",
    POS_ORDER_ALERT_FCM_SERVICE_ACCOUNT: JSON.stringify({ type: "service_account", project_id: "synthetic-project",
      client_email: "synthetic@synthetic-project.iam.gserviceaccount.com", private_key: ["-----BEGIN", "PRIVATE KEY-----\nSYNTHETIC"].join(" "),
      token_uri: "https://oauth2.googleapis.com/token" }),
    CRON_SECRET: CRON, POS_ALERT_CRON_ENABLED: "true", POS_ALERT_DISPATCH_URL: DISPATCH_URL, VERCEL: "1", VERCEL_ENV: "production" };
  const now = () => clock;
  function ensureRow(request, kind) {
    const key = `${request.id}/${kind}`;
    if (!rows.has(key)) rows.set(key, { delivery_id: id(serial++), registration_id: id(1), generation: id(2),
      request_id: request.id, kind, fcm_token: "synthetic-fcm-token-123456789", expires_at: request.expires_at,
      authority_expires_at: "2026-10-17T10:00:00Z", state: "queued", attempt: 0, next: 0, leaseUntil: 0 });
  }
  function claim(limit) {
    assert.equal(limit, 10, "existing batch contract is unchanged");
    if (!operator || !registered) return [];
    for (const request of requests.values()) {
      if (request.status === "pending" && Date.parse(request.expires_at) > clock) ensureRow(request, "pending");
      else if (rows.has(`${request.id}/pending`)) ensureRow(request, "terminal");
    }
    const batch = [];
    for (const row of rows.values()) {
      const request = requests.get(row.request_id);
      if (row.kind === "pending" && (request.status !== "pending" || Date.parse(row.expires_at) <= clock)) continue;
      if (!["queued", "leased"].includes(row.state) || row.next > clock || row.leaseUntil > clock || row.attempt >= 3) continue;
      row.state = "leased"; row.attempt++; row.lease_id = id(serial++); row.leaseUntil = clock + 120_000;
      batch.push({ ...row });
      if (batch.length === limit) break;
    }
    return batch;
  }
  let worker;
  const fetchImpl = async (url, init) => {
    calls.push(url);
    if (url === DISPATCH_URL) {
      assert.equal(init.body, "{}"); assert.equal(init.headers.Authorization, `Bearer ${WORKER}`);
      if (dropWake) throw new Error("synthetic lost wake");
      return worker(new Request(url, init));
    }
    if (url.includes("fcm.googleapis.com")) {
      sends.push(JSON.parse(init.body).message);
      return fcmStatus === 200 ? Response.json({ name: "projects/synthetic-project/messages/1" }) : Response.json({}, { status: fcmStatus });
    }
    assert.equal(init.headers.Authorization, "Bearer synthetic-server-key");
    const args = JSON.parse(init.body);
    if (url.endsWith("/submit_web_order_platform_request")) {
      const replayed = requests.size > 0;
      if (!replayed) requests.set(id(10), { id: id(10), status: "pending", expires_at: "2026-10-17T09:15:00Z" });
      return Response.json({ ok: true, request_id: clientId, replayed, status: "pending", expires_at: "2026-10-17T09:15:00Z",
        totals: { currency_code: "ILS", subtotal_minor: 1000, tax_total_minor: 0, grand_total_minor: 1000 } });
    }
    if (url.endsWith("/pos_claim_order_alert_deliveries")) return Response.json({ ok: true, deliveries: claim(args.p_limit) });
    if (url.endsWith("/pos_finish_order_alert_delivery")) {
      if (failNextFinish) { failNextFinish = false; throw new Error("synthetic lost finish outcome"); }
      const row = [...rows.values()].find((row) => row.delivery_id === args.p_delivery_id);
      assert.equal(row.state, "leased"); assert.equal(args.p_lease_id, row.lease_id);
      row.state = args.p_outcome === "sent" ? "sent" : args.p_outcome === "retry" && row.attempt < 3 ? "queued" : "abandoned";
      row.leaseUntil = 0; row.next = clock + 60_000;
      if (args.p_outcome === "invalid_token") registered = false;
      return Response.json({ ok: true });
    }
    throw new Error("unexpected API: no order acceptance, printing, status, or other RPC permitted");
  };
  worker = dispatchHandler({ getEnv: (n) => env[n], now, fetchImpl, cryptoImpl: webcrypto, tokenProvider: async () => "synthetic-access-token" });
  const submit = submissionHandler({ getEnv: (n) => env[n], now, fetchImpl, cryptoImpl: webcrypto,
    waitUntil: (task) => { tasks.push(task); } });
  // Same real Cron handler but route its one HTTP POST to the in-memory worker.
  const cronEnv = { ...env }; // Independent deployment snapshot, like real Vercel.
  const cron = cronHandler({ getEnv: (n) => cronEnv[n], now, fetchImpl: async (url, init) => {
    assert.equal(url, DISPATCH_URL); assert.equal(init.body, "{}");
    return worker(new Request(url, init));
  } });
  return { env, calls, sends, rows, requests, tasks,
    submit: () => submit(post("https://edge.invalid/web-order-submit", makeRequest())),
    tick: () => cron(new Request("https://cron.invalid/api/dispatch", { headers: { Authorization: `Bearer ${CRON}` } })),
    advance: (ms) => { clock += ms; }, failFinish: () => { failNextFinish = true; },
    authorize: (on) => { operator = on; registered = on; } };
}

test("concurrent instant wake and real Cron handler share one lease, one FCM hint, max-ten batch contract", async () => {
  const h = fixture();
  assert.equal((await h.submit()).status, 200);
  await Promise.all([...h.tasks, h.tick()]);
  assert.equal(h.sends.length, 1); assert.equal(h.rows.size, 1);
  assert.equal([...h.rows.values()][0].attempt, 1);
  assert.equal(h.sends[0].data.kind, "pending");
  assert.ok(h.calls.every((url) => !/(accept_web_order|print|payment|disable_order_alert)/.test(url)));
});

test("lost post-commit wake recovers through Cron; replay creates no second wake or delivery", async () => {
  const h = fixture({ dropWake: true });
  assert.equal((await h.submit()).status, 200); await Promise.all(h.tasks);
  assert.equal(h.requests.size, 1); assert.equal(h.sends.length, 0);
  assert.equal((await h.tick()).status, 200); assert.equal(h.sends.length, 1);
  await h.submit(); assert.equal(h.tasks.length, 1);
  await h.tick(); assert.equal(h.sends.length, 1);
});

test("instant opt-in OFF leaves the existing Cron recovery path available", async () => {
  const h = fixture(); h.env.POS_ORDER_ALERT_INSTANT_WAKE_ENABLED = "false";
  await h.submit(); assert.equal(h.tasks.length, 0); assert.equal(h.sends.length, 0);
  assert.equal((await h.tick()).status, 200); assert.equal(h.sends.length, 1);
});

test("unknown finish never bypasses active lease; Cron recovery can duplicate hints after lease expiry", async () => {
  const h = fixture(); h.failFinish();
  await h.submit(); await Promise.all(h.tasks); assert.equal(h.sends.length, 1);
  await h.tick(); assert.equal(h.sends.length, 1);
  h.advance(120_001); await h.tick();
  assert.equal(h.sends.length, 2, "FCM hints are not exactly once; database lease is retained, not overridden");
  assert.equal([...h.rows.values()][0].attempt, 2);
});

test("FCM transient failure waits for later Cron retry, maximum three existing attempts", async () => {
  const h = fixture({ fcmStatus: 503 });
  await h.submit(); await Promise.all(h.tasks); assert.equal(h.sends.length, 1);
  await h.tick(); assert.equal(h.sends.length, 1);
  for (let n = 0; n < 3; n++) { h.advance(60_000); await h.tick(); }
  assert.equal(h.sends.length, 3); assert.equal([...h.rows.values()][0].attempt, 3);
});

for (const terminal of ["accepted", "rejected", "expired"]) test(`Cron handles ${terminal} cancellation without another submit/wake`, async () => {
  const h = fixture(); await h.submit(); await Promise.all(h.tasks);
  const request = [...h.requests.values()][0];
  if (terminal === "expired") h.advance(15 * 60_000); else request.status = terminal;
  await h.tick();
  assert.equal(h.tasks.length, 1); assert.equal(h.sends.length, 2);
  assert.equal(h.sends[1].data.kind, "cancel");
  assert.equal(h.sends[1].data.request_id, request.id);
  assert.notEqual(h.sends[0].android.collapse_key, h.sends[1].android.collapse_key);
});

test("terminal A does not suppress still-pending B in a later Cron batch", async () => {
  const h = fixture(); await h.submit(); await Promise.all(h.tasks);
  const a = [...h.requests.values()][0]; a.status = "accepted";
  h.requests.set(id(11), { id: id(11), status: "pending", expires_at: "2026-10-17T09:15:00Z" });
  await h.tick();
  assert.equal(h.sends.length, 3);
  const pendingB = h.sends.find((message) => message.data.request_id === id(11));
  const terminalA = h.sends.find((message) => message.data.request_id === a.id && message.data.kind === "cancel");
  assert.equal(pendingB.data.kind, "pending"); assert.ok(terminalA);
  assert.notEqual(pendingB.android.collapse_key, terminalA.android.collapse_key);
});

test("operator/registration authorization remains in existing claim authority", async () => {
  const h = fixture({ enabled: false }); await h.submit(); await Promise.all(h.tasks);
  assert.equal(h.sends.length, 0); assert.equal(h.rows.size, 0);
  await h.tick(); assert.equal(h.sends.length, 0);
  assert.equal(h.calls.some((url) => url.endsWith("/pos_claim_order_alert_deliveries")), true);
});

test("Edge pilot cutoff denies Cron even if Vercel's configured window differs", async () => {
  const h = fixture({ dropWake: true }); await h.submit(); await Promise.all(h.tasks);
  h.env.POS_ALERT_PILOT_END_UTC = "2026-10-17T09:00:01Z";
  assert.equal((await h.tick()).status, 502); assert.equal(h.sends.length, 0);
  assert.equal(h.calls.some((url) => url.endsWith("/pos_claim_order_alert_deliveries")), false);
});
