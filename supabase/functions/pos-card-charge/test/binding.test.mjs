// The same-request caller binding (DECISION D-060 point 2; API_CONTRACT section 4.55.2): taken
// only from the successful context proof of THIS request, never a body value, a cached proof or
// another request's binding; the transport principal is not the PIN employee; each service call
// is a single PostgREST RPC (one READ COMMITTED transaction - wiring only, not hosted isolation).
import "./no_network.mjs";
import test from "node:test";
import assert from "node:assert/strict";
import { adapterRead, ANON, BASE, blocked, CALLER, contextAttempt, contextOk, EMPLOYEE, envelope, freeInput,
  freshClaim, id, MEMBERSHIP, providerReply, releaseInput, SERVICE, settleAll, startTest, statusInput, stray, TIMING,
  world } from "./fixtures.mjs";
import { isProven, proveContext } from "../lib/caller.mjs";
import { openLedger, serviceKeySource } from "../lib/ledger.mjs";
import { allowlistedEnv } from "../lib/config.mjs";

test.after(async () => { await settleAll(); assert.deepEqual(blocked, []); assert.deepEqual(stray, []); });

const SESSION_PROVING = ["card_attempt_claim", "card_attempt_adapter_read", "card_attempt_mark_release_requested",
  "card_attempt_mark_recording_result", "card_attempt_free_order"];

test("every session-proving call carries the proof's transport principal - never the PIN employee or membership", async () => {
  const runs = [
    [startTest(), { card_attempt_context: contextOk(), card_attempt_claim: freshClaim(),
      card_attempt_finish: envelope("approved") }, { commit: providerReply() }],
    [statusInput(), { card_attempt_context: contextOk({ attempt: contextAttempt("unknown") }),
      card_attempt_adapter_read: adapterRead("unknown"), card_attempt_finish: envelope("unknown") },
    { lookup: { SynError: true, SynReturn: -404 } }],
    [statusInput({ recording_refused: true, refusal_code: "permission_denied" }), {
      card_attempt_context: contextOk({ attempt: contextAttempt("approved", "live") }),
      card_attempt_adapter_read: adapterRead("approved", "live"),
      card_attempt_mark_recording_result: envelope("approved", { mode: "live" }) }, {}],
    [releaseInput(), { card_attempt_context: contextOk({ attempt: contextAttempt("sent") }),
      card_attempt_adapter_read: adapterRead("sent"), card_attempt_mark_release_requested: envelope("sent"),
      card_attempt_finish: envelope("released") }, { release: { SynError: false, SynReturn: 0 } }],
    [freeInput(), { card_attempt_context: contextOk({ role: "manager" }),
      card_attempt_free_order: envelope("unknown", { mode: "live", classification: "freed" }) }, {}],
  ];
  const seen = new Set();
  for (const [input, rpc, provider] of runs) {
    const w = world({ rpc, provider });
    await w.run(input);
    await w.settle();
    for (const call of w.calls.rpc) {
      if (SESSION_PROVING.includes(call.name)) {
        seen.add(call.name);
        assert.equal(call.body.p_caller_auth_user_id, CALLER, call.name);
        assert.ok(!call.raw.includes(EMPLOYEE) && !call.raw.includes(MEMBERSHIP), call.name);
        assert.equal(call.headers.apikey, SERVICE);
      } else if (call.name === "card_attempt_context") {
        assert.equal(call.headers.apikey, ANON, "the proof never uses the service key");
        assert.ok(!JSON.stringify(call.headers).includes(SERVICE));
      } else {
        assert.equal(call.name, "card_attempt_finish");
        assert.ok(!("p_caller_auth_user_id" in call.body));
      }
      assert.ok(!("Prefer" in call.headers) && !("prefer" in call.headers), "no transaction or isolation header");
    }
  }
  assert.deepEqual([...seen].sort(), [...SESSION_PROVING].sort());
});

test("parallel requests each carry their own proof's binding, even when they interleave (start, status, release)", async () => {
  const callers = { "Bearer synthetic.caller.one": id(101), "Bearer synthetic.caller.two": id(102) };
  const pins = { [id(101)]: id(201), [id(102)]: id(202) }; // each request's own PIN session, to correlate its calls
  for (const [input, first, answer, attempt] of [
    [startTest, "card_attempt_claim", () => ({ ...freshClaim(), claim_created: false, replayed: true }), null],
    [statusInput, "card_attempt_adapter_read", () => adapterRead("approved"), contextAttempt("approved")],
    [releaseInput, "card_attempt_adapter_read",
      () => adapterRead("sent", "test", { release_requested_at: "2026-10-27T10:00:00.100000+00:00" }), contextAttempt("sent")],
  ]) {
    // Deterministic interleaving: request one's proof answers only once request two has reached its service call.
    let reached;
    const secondReached = new Promise((resolve) => { reached = resolve; });
    const w = world({ timing: { ...TIMING, rpcMs: 5_000 }, rpc: {
      card_attempt_context: async (_body, init) => {
        const caller = callers[init.headers.Authorization];
        if (caller === id(101)) await secondReached;
        return Response.json(contextOk({ caller_auth_user_id: caller, attempt }));
      },
      [first]: (body) => { if (body.p_caller_auth_user_id === id(102)) reached(); return answer(); },
    } });
    const [one, two] = await Promise.all([w.run(input({ pin_session_id: pins[id(101)] }), { jwt: "synthetic.caller.one" }),
      w.run(input({ pin_session_id: pins[id(102)] }), { jwt: "synthetic.caller.two" })]);
    assert.equal(one.status, 200, input.name);
    assert.equal(two.status, 200, input.name);
    const calls = w.calls.rpc.filter((call) => call.name === first);
    assert.equal(calls.length, 2, input.name);
    assert.equal(calls[0].body.p_caller_auth_user_id, id(102), "the second request reached its service call first");
    for (const call of calls) {
      assert.equal(pins[call.body.p_caller_auth_user_id], call.body.p_pin_session_id, "each call carries its own request's binding");
    }
  }
});

test("a proof is usable only by the request that produced it; a look-alike object is never a proof", async () => {
  const keySource = serviceKeySource((name) => ({ SUPABASE_SERVICE_ROLE_KEY: SERVICE })[name]);
  const requestA = Object.freeze({});
  const requestB = Object.freeze({});
  const fetchImpl = async () => Response.json(contextOk());
  const proof = await proveContext({ request: requestA, base: BASE, anonKey: ANON, authorization: "Bearer a.b.c", fetchImpl,
    deadlineMs: 100, maxBytes: 4096, args: { pinSessionId: id(6), deviceId: contextOk().device_id,
      deviceSessionToken: "t", orderId: null, attemptId: null } });
  assert.equal(proof.kind, "proven");
  assert.ok(isProven(proof.proven, requestA));
  assert.ok(!isProven(proof.proven, requestB), "another request cannot reuse (cache) this proof");
  const open = (proven, request, source = keySource) => openLedger({ keySource: source, fetchImpl, base: BASE, deadlineMs: 100,
    maxBytes: 4096, proven, request });
  assert.throws(() => open(proof.proven, requestB));
  const forged = { ...proof.proven };
  assert.ok(!isProven(forged, requestA));
  assert.throws(() => open(forged, requestA));
  assert.throws(() => open({ callerAuthUserId: CALLER, request: requestA }, requestA));
  const ledger = open(proof.proven, requestA);
  assert.ok(ledger && typeof ledger.claim === "function");
  assert.ok(!Object.values(ledger).some((value) => typeof value === "string"), "the ledger exposes no key or binding value");
  assert.equal(open(proof.proven, requestA, Object.freeze({})), null, "a look-alike key source unlocks nothing");
});

test("the service-role key is unreachable outside the ledger module", () => {
  const env = allowlistedEnv((name) => ({ SUPABASE_SERVICE_ROLE_KEY: SERVICE, SUPABASE_URL: BASE })[name]);
  assert.throws(() => env("SUPABASE_SERVICE_ROLE_KEY"), "the handler's accessor cannot read the key");
  assert.equal(env("SUPABASE_URL"), BASE);
  const source = serviceKeySource(() => SERVICE);
  assert.deepEqual(Object.keys(source), []);
  assert.ok(Object.isFrozen(source));
  assert.ok(!JSON.stringify(source).includes(SERVICE));
});

test("no service call follows a failed or support-refused proof, for every action", async () => {
  const inputs = [startTest(), statusInput(), releaseInput(), freeInput()];
  for (const answer of [{ ok: false, error: "permission_denied" }, { ok: false, error: "invalid_session" },
    new Response("{}", { status: 401 }), new Response("{}", { status: 500 })]) {
    for (const input of inputs) {
      const w = world({ rpc: { card_attempt_context: answer instanceof Response ? () => answer.clone() : answer } });
      const out = await w.run(input);
      assert.deepEqual(w.rpcNames(), ["card_attempt_context"], `${input.action} ${JSON.stringify(answer)}`);
      assert.deepEqual(w.calls.provider, []);
      assert.ok([200, 401, 503].includes(out.status));
    }
  }
});

test("the support refusal of the binding check inside a service call is surfaced unchanged", async () => {
  // card_caller_binding_denial answers permission_denied for an ACTIVE support session (D-060 point 2).
  const w = world({ rpc: { card_attempt_context: contextOk(), card_attempt_claim: { ok: false, error: "permission_denied",
    server_ts: "2026-10-27T10:00:00+00:00" } }, provider: { commit: providerReply() } });
  const out = await w.run(startTest());
  assert.deepEqual(out.body, { ok: false, error: "permission_denied", server_ts: "2026-10-27T10:00:00+00:00" });
  assert.deepEqual(w.calls.provider, []);
  const read = world({ rpc: { card_attempt_context: contextOk({ attempt: contextAttempt("unknown") }),
    card_attempt_adapter_read: { ok: false, error: "permission_denied" } }, provider: { lookup: {} } });
  assert.deepEqual((await read.run(statusInput())).body, { ok: false, error: "permission_denied" });
  assert.deepEqual(read.calls.provider, []);
});

test("a missing or malformed service key fails closed after the proof, with no service call", async () => {
  for (const key of [undefined, "", "short", "has whitespace in the synthetic key"]) {
    const w = world({ env: { SUPABASE_SERVICE_ROLE_KEY: key }, rpc: { card_attempt_context: contextOk() } });
    const out = await w.run(startTest());
    assert.equal(out.status, 503);
    assert.deepEqual(w.rpcNames(), ["card_attempt_context"]);
  }
});
