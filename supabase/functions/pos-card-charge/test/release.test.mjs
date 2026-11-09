// `release` (API_CONTRACT section 4.55.6): advisory; only `sent` / `unknown` without a resolution;
// the adapter read, then the service-only mark, then ONE provider release, then the finish.
import "./no_network.mjs";
import test from "node:test";
import assert from "node:assert/strict";
import { adapterRead, assertCleanProviderRequests, ATTEMPT, blocked, CALLER, contextAttempt, contextOk, DEVICE,
  envelope, id, later, OTHER_DEVICE, PIN, PROVIDER_BASE, providerConfig, releaseInput, settleAll, stray,
  SYNTHETIC_PROFILE, TOKEN, world } from "./fixtures.mjs";

test.after(async () => { await settleAll(); assert.deepEqual(blocked, []); assert.deepEqual(stray, []); });

const scripted = (state = "sent", extra = {}) => ({
  card_attempt_context: contextOk({ attempt: contextAttempt(state) }),
  card_attempt_adapter_read: adapterRead(state),
  card_attempt_mark_release_requested: envelope(state),
  card_attempt_finish: (body) => envelope(body.p_outcome === "released" ? "released" : state,
    body.p_outcome === "release_failed" ? { refusal_code: "release_failed" } : {}),
  ...extra,
});

test("a release request: proof, adapter read, mark, one provider release, finish(release)", async () => {
  const w = world({ rpc: scripted(), provider: { release: { SynError: false, SynReturn: 0 } } });
  const out = await w.run(releaseInput());
  assert.equal(out.status, 200);
  assert.deepEqual(out.body, envelope("released"));
  assert.deepEqual(w.rpcNames(), ["card_attempt_context", "card_attempt_adapter_read",
    "card_attempt_mark_release_requested", "card_attempt_finish"]);
  const mark = w.calls.rpc[2];
  assert.deepEqual(mark.body, { p_pin_session_id: PIN, p_device_id: DEVICE, p_device_session_token: TOKEN,
    p_attempt_id: ATTEMPT, p_caller_auth_user_id: CALLER });
  assert.equal(w.calls.provider.length, 1);
  assert.equal(w.calls.provider[0].url, `${PROVIDER_BASE}/synthetic/release`);
  assert.equal(w.calls.provider[0].raw, '{"syn_terminal":"SYNTERM","syn_password":"SYNPASS-TEST","syn_pad":"PADSYNPAD1"}');
  assertCleanProviderRequests(assert, w);
  const finish = w.calls.rpc[3];
  assert.equal(finish.body.p_source, "release");
  assert.equal(finish.body.p_outcome, "released");
  assert.deepEqual(finish.body.p_provider_fields, {});
});

test("release stays available under the kill switch", async () => {
  const w = world({ env: { POS_CARD_PAYMENTS_ENABLED: undefined }, rpc: scripted(),
    provider: { release: { SynError: false, SynReturn: 0 } } });
  assert.deepEqual((await w.run(releaseInput())).body, envelope("released"));
  assert.equal(w.calls.provider.length, 1);
});

test("an unconfirmed release answers release_failed with the state unchanged; never a retry", async () => {
  for (const reply of [{ SynError: true, SynReturn: -5 }, { SynError: false, SynReturn: -5 }, { SynError: true, SynReturn: 0 },
    {}, { SynReturn: 0 }, later(5000, () => Response.json({ SynError: false, SynReturn: 0 })), () => { throw new TypeError("reset"); },
    () => new Response(JSON.stringify({ SynError: false, SynReturn: 0 }), { status: 500 }),
    () => new Response("not json", { status: 200 })]) {
    const w = world({ rpc: scripted("unknown"), provider: { release: reply } });
    const out = await w.run(releaseInput());
    assert.equal(out.body.state, "unknown");
    assert.equal(out.body.refusal_code, "release_failed");
    assert.equal(w.calls.provider.length, 1);
    assert.equal(w.calls.rpc.filter((call) => call.name === "card_attempt_finish")[0].body.p_outcome, "release_failed");
  }
});

test("a non-releasable or resolved attempt answers its envelope with no adapter read, write or provider call", async () => {
  for (const [state, extra] of [["approved", {}], ["declined", {}], ["released", {}],
    ["unknown", { resolution: "test_closed" }], ["sent", { resolution: "test_closed" }]]) {
    const w = world({ rpc: scripted(state, { card_attempt_context: contextOk({ attempt: contextAttempt(state, "test", extra) }) }),
      provider: { release: { SynError: false, SynReturn: 0 } } });
    const out = await w.run(releaseInput());
    assert.equal(out.status, 200);
    assert.equal(out.body.state, state);
    assert.equal(out.body.server_ts, contextOk().server_ts);
    assert.deepEqual(w.rpcNames(), ["card_attempt_context"]);
    assert.deepEqual(w.calls.provider, []);
  }
  const missing = world({ rpc: scripted("sent", { card_attempt_context: contextOk({ attempt: null }) }) });
  assert.deepEqual((await missing.run(releaseInput())).body, { ok: false, error: "attempt_not_found" });
  assert.deepEqual(missing.rpcNames(), ["card_attempt_context"]);
});

test("a missing or mismatched record, no profile, no release route or an incomplete OWN record: no mark, no provider call", async () => {
  const sqlRefusal = world({ rpc: scripted("sent", { card_attempt_adapter_read: { ok: false, error: "provider_unavailable",
    attempt_id: ATTEMPT, attempt_state: "sent" } }), provider: { release: {} } });
  assert.equal((await sqlRefusal.run(releaseInput())).status, 503);
  assert.deepEqual(sqlRefusal.rpcNames(), ["card_attempt_context", "card_attempt_adapter_read"]);
  assert.deepEqual(sqlRefusal.calls.provider, []);
  const noProfile = world({ profile: null, rpc: scripted("sent"), provider: { release: {} } });
  const out = await noProfile.run(releaseInput());
  assert.deepEqual(out.body, { ok: false, error: "provider_unavailable", attempt_id: ATTEMPT, attempt_state: "sent" });
  assert.deepEqual(noProfile.rpcNames(), ["card_attempt_context", "card_attempt_adapter_read"]);
  const noRoute = world({ profile: { ...SYNTHETIC_PROFILE, routes: { ...SYNTHETIC_PROFILE.routes, release: null },
    request: { ...SYNTHETIC_PROFILE.request, release: null } }, rpc: scripted("sent"), provider: { release: {} } });
  assert.equal((await noRoute.run(releaseInput())).status, 503);
  assert.deepEqual(noRoute.rpcNames(), ["card_attempt_context", "card_attempt_adapter_read"]);
  assert.deepEqual(noRoute.calls.provider, []);
  const own = providerConfig({ credentials: { ...providerConfig().credentials,
    "cred-test": { mode: "test", scope: "development", secret: { terminal: "SYNTERM" } } } });
  const incomplete = world({ env: { POS_CARD_PROVIDER_CONFIG: JSON.stringify(own) }, rpc: scripted("sent"), provider: { release: {} } });
  assert.equal((await incomplete.run(releaseInput())).status, 503);
  assert.deepEqual(incomplete.rpcNames(), ["card_attempt_context", "card_attempt_adapter_read"]);
  // An unrelated incomplete record never blocks this attempt's release.
  const unrelated = providerConfig({ credentials: { ...providerConfig().credentials,
    "cred-other": { mode: "live", scope: "merchant", restaurant_id: id(77), secret: { terminal: "SYNOTHER" } } } });
  const fine = world({ env: { POS_CARD_PROVIDER_CONFIG: JSON.stringify(unrelated) }, rpc: scripted("sent"),
    provider: { release: { SynError: false, SynReturn: 0 } } });
  assert.deepEqual((await fine.run(releaseInput())).body, envelope("released"));
});

test("a service read outside the proof's scope is never released", async () => {
  for (const [patch, role] of [[{ organization_id: id(90) }, "cashier"], [{ restaurant_id: id(91) }, "cashier"],
    [{ device_id: OTHER_DEVICE }, "cashier"], [{ organization_id: id(90) }, "manager"], [{ restaurant_id: id(91) }, "manager"],
    [{ restaurant_id: id(91) }, "restaurant_owner"], [{ restaurant_id: id(91) }, "org_owner"]]) {
    const w = world({ rpc: scripted("sent", { card_attempt_context: contextOk({ role, attempt: contextAttempt("sent") }),
      card_attempt_adapter_read: adapterRead("sent", "test", patch) }), provider: { release: {} } });
    assert.equal((await w.run(releaseInput())).status, 503, `${role} ${JSON.stringify(patch)}`);
    assert.deepEqual(w.calls.provider, []);
    assert.ok(!w.rpcNames().includes("card_attempt_mark_release_requested"));
    assert.ok(!w.rpcNames().includes("card_attempt_finish"));
  }
});

test("a release requested within the minimum interval answers the envelope: no mark and no provider call", async () => {
  const w = world({ rpc: scripted("sent", { card_attempt_adapter_read: adapterRead("sent", "test", {
    release_requested_at: "2026-10-27T10:00:09.000000+00:00", server_ts: "2026-10-27T10:00:10.000000+00:00" }) }),
  provider: { release: {} } });
  assert.equal((await w.run(releaseInput())).body.state, "sent");
  assert.deepEqual(w.rpcNames(), ["card_attempt_context", "card_attempt_adapter_read"]);
  assert.deepEqual(w.calls.provider, []);
  const after = world({ rpc: scripted("sent", { card_attempt_adapter_read: adapterRead("sent", "test", {
    release_requested_at: "2026-10-27T10:00:05.000000+00:00", server_ts: "2026-10-27T10:00:10.000000+00:00" }) }),
  provider: { release: { SynError: false, SynReturn: 0 } } });
  assert.deepEqual((await after.run(releaseInput())).body, envelope("released"));
});

test("a mark refusal or an attempt that changed under the mark stops before the provider", async () => {
  const refused = world({ rpc: scripted("sent", { card_attempt_mark_release_requested: { ok: false, error: "permission_denied" } }),
    provider: { release: {} } });
  assert.deepEqual((await refused.run(releaseInput())).body, { ok: false, error: "permission_denied" });
  assert.deepEqual(refused.calls.provider, []);
  const changed = world({ rpc: scripted("sent", { card_attempt_mark_release_requested: envelope("approved") }),
    provider: { release: {} } });
  assert.deepEqual((await changed.run(releaseInput())).body, envelope("approved"));
  assert.deepEqual(changed.calls.provider, []);
  assert.ok(!changed.rpcNames().includes("card_attempt_finish"));
});

test("an absent or unreadable release stamp fails closed; a stamp ahead of the database clock never suppresses a release", async () => {
  const read = (extra) => adapterRead("sent", "test", { server_ts: "2026-10-27T10:00:10.000000+00:00", ...extra });
  const absent = read({});
  delete absent.release_requested_at;
  for (const [answer, label] of [[absent, "absent key"], [read({ release_requested_at: "yesterday" }), "unreadable"]]) {
    const w = world({ rpc: scripted("sent", { card_attempt_adapter_read: answer }), provider: { release: { SynError: false, SynReturn: 0 } } });
    const out = await w.run(releaseInput());
    assert.equal(out.status, 503, label);
    assert.deepEqual(out.body, { ok: false, error: "unavailable" });
    assert.deepEqual(w.rpcNames(), ["card_attempt_context", "card_attempt_adapter_read"], label);
    assert.deepEqual(w.calls.provider, []);
  }
  const ahead = world({ rpc: scripted("sent", { card_attempt_adapter_read: read({
    release_requested_at: "2026-10-27T11:00:10.000000+00:00" }) }), provider: { release: { SynError: false, SynReturn: 0 } } });
  assert.deepEqual((await ahead.run(releaseInput())).body, envelope("released"));
  assert.equal(ahead.calls.provider.length, 1, "a clock stepped back never suppresses a release");
});

test("a release inside the interval is not a confirmation: the stored state, no refusal code, nothing sent", async () => {
  // The mark of a first release commits but its answer is lost (503); a retry inside 3 s answers the stored
  // envelope with no mark and no provider call - only state 'released' confirms (section 4.55.6).
  const w = world({ rpc: scripted("sent", { card_attempt_adapter_read: adapterRead("sent", "test", {
    release_requested_at: "2026-10-27T10:00:09.000000+00:00", server_ts: "2026-10-27T10:00:10.000000+00:00" }) }),
  provider: { release: { SynError: false, SynReturn: 0 } } });
  const out = await w.run(releaseInput());
  assert.equal(out.status, 200);
  assert.deepEqual(out.body, envelope("sent", { server_ts: "2026-10-27T10:00:10.000000+00:00" }));
  assert.ok(!("refusal_code" in out.body));
  assert.deepEqual(w.calls.provider, []);
});

test("a credential of another mode behind the attempt's own terminal: provider_unavailable with no mark", async () => {
  const other = providerConfig({ credentials: { ...providerConfig().credentials,
    "cred-test": { mode: "live", scope: "merchant", restaurant_id: id(2), secret: { terminal: "SYNTERM", password: "SYNPASS-TEST" } } } });
  const w = world({ env: { POS_CARD_PROVIDER_CONFIG: JSON.stringify(other) }, rpc: scripted("sent"), provider: { release: {} } });
  const out = await w.run(releaseInput());
  assert.deepEqual(out.body, { ok: false, error: "provider_unavailable", attempt_id: ATTEMPT, attempt_state: "sent" });
  assert.deepEqual(w.rpcNames(), ["card_attempt_context", "card_attempt_adapter_read"]);
  assert.deepEqual(w.calls.provider, []);
});

test("typed finish answers after a release are unavailable or the resolved envelope; nothing is resent", async () => {
  const unavailable = { ok: false, error: "unavailable" };
  const resolved = envelope("unknown", { resolution: "test_closed" });
  for (const [finish, status, body] of [[new Response("{}", { status: 500 }), 503, unavailable],
    [{ ok: false, error: "conflict", detail: "attempt_scope_mismatch", server_ts: "2026-10-27T10:00:00+00:00" }, 503, unavailable],
    [{ ok: false, error: "attempt_not_found" }, 503, unavailable], [{ ok: false, error: "invalid_request" }, 503, unavailable],
    [resolved, 200, resolved]]) {
    const w = world({ rpc: scripted("sent", { card_attempt_finish: finish instanceof Response ? () => finish.clone() : finish }),
      provider: { release: { SynError: false, SynReturn: 0 } } });
    const out = await w.run(releaseInput());
    assert.equal(out.status, status);
    assert.deepEqual(out.body, body);
    assert.deepEqual(w.rpcNames(), ["card_attempt_context", "card_attempt_adapter_read", "card_attempt_mark_release_requested",
      "card_attempt_finish"]);
    assert.equal(w.calls.provider.length, 1);
    assert.ok(!out.text.includes("attempt_scope_mismatch"));
  }
});
