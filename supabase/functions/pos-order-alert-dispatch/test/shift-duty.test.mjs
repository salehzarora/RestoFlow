import test from "node:test";
import assert from "node:assert/strict";
import { webcrypto } from "node:crypto";
import { createHandler } from "../../pos-order-alert-status/handler.mjs";
import { message } from "../fcm.mjs";

const id = (n) => `41000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
const input = { installation_id: id(1), consent_id: id(2) };
const bound = {
  ok: true, consent_id: id(2), registration_id: id(3), generation: id(4),
  server_time: "2026-11-06T12:30:00Z", authority_expires_at: "2026-11-06T18:00:00Z",
};
const token = "synthetic-rotated-routing-address";
test("duty wakes carry consent and transport identities, legacy wakes keep their exact schema", () => {
  const delivery = { registration_id: id(3), generation: id(4), request_id: id(5), delivery_id: id(6), lease_id: id(7),
    kind: "pending", fcm_token: token, expires_at: bound.authority_expires_at, authority_expires_at: bound.authority_expires_at };
  const now = Date.parse(bound.server_time);
  const legacy = message(delivery, now).message.data;
  assert.deepEqual(Object.keys(legacy).sort(), ["expires_at","kind","registration_id","request_id","version"]);
  for (const kind of ["pending","terminal"]) {
    const wake = message({ ...delivery, kind, consent_id: id(2) }, now).message;
    assert.deepEqual(wake.data, { ...legacy, version: "2", kind: kind === "pending" ? kind : "cancel", consent_id: id(2), generation: id(4) });
    assert.ok(parseInt(wake.android.ttl) <= 120);
  }
  for (const consent_id of [null, false, [id(2)], ""]) assert.throws(() => message({ ...delivery, consent_id }, now));
});
const request = (route, body, secret = "a".repeat(64)) => new Request(
  "https://example.invalid/functions/v1/pos-order-alert-status/duty/" + route,
  { method: "POST", headers: { Authorization: "Bearer " + secret }, body: JSON.stringify(body) }
);
function fixture(answer, enabled = true) {
  const calls = [];
  const env = { SUPABASE_SERVICE_ROLE_KEY: "mock", SUPABASE_URL: "http://localhost:54321",
    POS_ORDER_ALERTS_ENABLED: enabled ? "true" : "false" };
  const handle = createHandler({ getEnv: key => env[key], cryptoImpl: webcrypto, fetchImpl: async (url, init) => {
    calls.push({ rpc: new URL(url).pathname.split("/").at(-1), args: JSON.parse(init.body) });
    return Response.json(answer);
  } });
  return { calls, handle };
}

test("a duty status read binds the consent and transport result, with a bounded projection", async () => {
  const requests = [{ request_id: id(5), expires_at: "2026-11-06T12:35:00Z" }];
  const { handle, calls } = fixture({ ...bound, requests: [{ ...requests[0], customer: "private" }], secret: "redacted" });
  const response = await handle(request("status", input));
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { ...bound, requests });
  assert.equal(calls[0].rpc, "pos_shift_order_alert_status");
  assert.equal(calls[0].args.p_consent_id, input.consent_id);
  assert.equal(calls[0].args.p_installation_id, input.installation_id);
  assert.match(calls[0].args.p_status_secret_hash, /^[a-f0-9]{64}$/);
});

test("token rotation uses old transport generation and never requests a new consent", async () => {
  const { handle, calls } = fixture(bound);
  const response = await handle(request("token/refresh", { ...input, generation: id(9), fcm_token: token }));
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), bound);
  assert.equal(calls[0].rpc, "pos_refresh_shift_order_alert_token");
  assert.equal(calls[0].args.p_expected_generation, id(9));
  assert.equal(calls[0].args.p_consent_id, id(2));
});

test("a stable revoke-only request works with master switch OFF and echoes only its consent", async () => {
  const { handle, calls } = fixture({ ok: true, consent_id: id(2), unrelated: true }, false);
  for (let retry = 0; retry < 2; retry++) {
    const response = await handle(request("revoke", input, "b".repeat(64)));
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), { ok: true, consent_id: id(2) });
  }
  assert.deepEqual(calls[0], calls[1]);
  assert.equal(calls[0].rpc, "pos_revoke_shift_order_alert");
  assert.deepEqual(Object.keys(calls[0].args).sort(), ["p_consent_id","p_installation_id","p_revoke_hash"]);
});

test("mismatched consent, non-Boolean success, malformed capacity or expiry do not grant or acknowledge", async () => {
  for (const result of [{ ...bound, consent_id: id(8), requests: [] }, { ok: "true" }, { ok: null }, {},
    { ...bound, generation: [id(4)], requests: [] }, { ...bound, requests: Array(51).fill({}) },
    { ...bound, requests: [], authority_expires_at: bound.server_time }]) {
    assert.equal((await fixture(result).handle(request("status", input))).status, 503);
  }
  assert.equal((await fixture({ok:true,consent_id:id(8)}).handle(request("revoke", input))).status, 503);
  assert.equal((await fixture({ok:false,error:"unavailable"}).handle(request("revoke", input))).status, 503);
  assert.equal((await fixture({ok:false,error:"unauthorized"}).handle(request("revoke", input))).status, 401);
});

test("wrong input types, fields or operations never reach an RPC", async () => {
  const { handle, calls } = fixture(bound);
  for (const invalid of [{...input,consent_id:[id(2)]},{...input,extend:true},{installation_id:id(1)}, {...input,consent_id:null}]) {
    assert.equal((await handle(request("status", invalid))).status, 400);
  }
  assert.equal((await handle(request("pay", input))).status, 404);
  assert.equal(calls.length, 0);
});
