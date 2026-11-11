// `status` (API_CONTRACT section 4.55.5): the proof, the adapter read with the configuration maps,
// one lookup by the STORED key under the attempt's FROZEN references for every provider-bound
// state (sent, unknown, released), the outcome mapping, the poll cap and cadence, and the
// recording-refused report (section 4.55.7).
import "./no_network.mjs";
import test from "node:test";
import assert from "node:assert/strict";
import { adapterRead, assertCleanProviderRequests, ATTEMPT, blocked, CALLER, contextAttempt, contextOk, DEVICE,
  envelope, freshClaim, id, LIVE_ENV, never, numberToken, OTHER_DEVICE, PIN, PROVIDER_BASE, providerConfig, providerReply,
  QUERY_KEY, REST, ROW, SERVICE, settleAll, startTest, statusInput, stray, TIMING, TOKEN, world } from "./fixtures.mjs";

test.after(async () => { await settleAll(); assert.deepEqual(blocked, []); assert.deepEqual(stray, []); });

const lookupEcho = (body) => {
  const state = { approved: "approved", declined: "declined", anomaly: "unknown" }[body.p_outcome] ?? "unknown";
  return envelope(state, { mode: body.p_mode });
};
const scripted = (state = "unknown", mode = "test", extra = {}) => ({
  card_attempt_context: contextOk({ attempt: contextAttempt(state, mode) }),
  card_attempt_adapter_read: adapterRead(state, mode),
  card_attempt_finish: lookupEcho,
  ...extra,
});
// The amount is a JSON number token (DECISION D-064: a JSON string amount is a format failure).
const found = (fields = {}) => ({ SynError: false, SynReturn: 0, SynStatus: "S1", SynAmount: numberToken("12.34"), SynCurrency: 1,
  ...fields });
const finishOf = (w) => w.calls.rpc.filter((call) => call.name === "card_attempt_finish");
const lookupOutcome = async (reply, mode = "test") => {
  const w = world({ ...(mode === "live" ? { env: LIVE_ENV } : {}), rpc: scripted("unknown", mode), provider: { lookup: reply } });
  await w.run(statusInput());
  return finishOf(w)[0].body;
};

test("context first (with the attempt id), then the adapter read with the maps and the same request's binding", async () => {
  const w = world({ rpc: scripted(), provider: { lookup: found() } });
  const out = await w.run(statusInput());
  assert.equal(out.status, 200);
  const [context, read, finish] = w.calls.rpc;
  assert.deepEqual(context.body, { p_pin_session_id: PIN, p_device_id: DEVICE, p_device_session_token: TOKEN,
    p_order_id: null, p_attempt_id: ATTEMPT });
  assert.equal(read.name, "card_attempt_adapter_read");
  assert.equal(read.headers.Authorization, `Bearer ${SERVICE}`);
  assert.deepEqual(read.body, { p_pin_session_id: PIN, p_device_id: DEVICE, p_device_session_token: TOKEN,
    p_attempt_id: ATTEMPT, p_environment: "test", p_terminals: { "pad-test": "cred-test", "pad-live": "cred-live" },
    p_credentials: { "cred-test": { mode: "test", scope: "development" },
      "cred-live": { mode: "live", scope: "merchant", restaurant_id: REST } },
    p_caller_auth_user_id: CALLER });
  assert.equal(finish.body.p_source, "lookup");
  assert.equal(finish.body.p_poll_source, "auto");
  assert.equal(finish.body.p_attempt_row_id, ROW);
  assert.equal(w.calls.provider.length, 1);
  assert.equal(w.calls.provider[0].url, `${PROVIDER_BASE}/synthetic/lookup`);
  assert.equal(w.calls.provider[0].raw, `{"syn_terminal":"SYNTERM","syn_password":"SYNPASS-TEST","syn_query":"${QUERY_KEY}"}`);
  assertCleanProviderRequests(assert, w);
});

test("every provider-bound state is looked up once: sent (before and after its deadline), unknown and released", async () => {
  for (const [state, extra] of [["sent", { start_deadline_passed: false }], ["sent", { start_deadline_passed: true }],
    ["unknown", {}], ["released", {}]]) {
    for (const source of ["auto", "operator"]) {
      const w = world({ rpc: scripted(state, "test", { card_attempt_adapter_read: adapterRead(state, "test", extra) }),
        provider: { lookup: { SynError: true, SynReturn: -102 } } });
      await w.run(statusInput({ source }));
      assert.equal(w.calls.provider.length, 1, `${state} ${source}`);
      assert.equal(w.calls.provider[0].body.syn_query, QUERY_KEY);
      const finishes = finishOf(w);
      assert.equal(finishes.length, 1);
      assert.equal(finishes[0].body.p_source, "lookup");
      assert.equal(finishes[0].body.p_outcome, "pending");
      assert.equal(finishes[0].body.p_poll_source, source);
    }
  }
});

test("a worker that dies mid-commit is recovered only by a later status lookup: zero further commits", async () => {
  // A commit budget far above the start window: the answer is 'sent' however the timers are scheduled.
  const w = world({ timing: { ...TIMING, commitBudgetMs: 1_000 }, rpc: { card_attempt_context: contextOk(),
    card_attempt_claim: freshClaim(), card_attempt_finish: envelope("unknown") }, provider: { commit: never } });
  const started = await w.run(startTest());
  assert.deepEqual(started.body, envelope("sent"));
  assert.equal(w.calls.provider.length, 1);
  assert.ok(!w.rpcNames().includes("card_attempt_finish"), "nothing finished the attempt when start answered");
  await w.settle(); // (in this harness the dead worker's deadline still fires; a real dead worker writes nothing)
  // The worker is gone: its commit task never settles and nothing finishes it. A new request recovers.
  const later = world({ rpc: scripted("sent", "test", { card_attempt_adapter_read: adapterRead("sent", "test",
    { start_deadline_passed: true }) }), provider: { lookup: found() } });
  const out = await later.run(statusInput());
  assert.equal(out.body.state, "approved");
  assert.deepEqual(later.calls.provider.map((call) => call.op), ["lookup"]);
  assert.deepEqual(later.rpcNames(), ["card_attempt_context", "card_attempt_adapter_read", "card_attempt_finish"]);
});

test("an attempt the proof cannot see answers attempt_not_found with no service call", async () => {
  const w = world({ rpc: scripted("sent", "test", { card_attempt_context: contextOk({ attempt: null }) }) });
  const out = await w.run(statusInput());
  assert.deepEqual(out.body, { ok: false, error: "attempt_not_found" });
  assert.deepEqual(w.rpcNames(), ["card_attempt_context"]);
});

test("adapter-read refusals are returned unchanged with zero provider calls", async () => {
  const position = { attempt_id: ATTEMPT, attempt_state: "unknown" };
  for (const [answer, status] of [
    [{ ok: false, error: "provider_unavailable", ...position, server_ts: "2026-10-27T10:00:00+00:00" }, 503],
    [{ ok: false, error: "attempt_not_found" }, 200],
    [{ ok: false, error: "conflict" }, 200],
    [{ ok: false, error: "invalid_session" }, 401],
    [{ ok: false, error: "permission_denied" }, 200],
  ]) {
    const w = world({ rpc: scripted("unknown", "test", { card_attempt_adapter_read: answer }), provider: { lookup: found() } });
    const out = await w.run(statusInput());
    assert.equal(out.status, status);
    assert.deepEqual(out.body, answer);
    assert.deepEqual(w.calls.provider, []);
    assert.equal(finishOf(w).length, 0);
  }
});

test("a service read outside the proof's scope is never acted on (foreign organization, restaurant or device)", async () => {
  for (const [patch, role] of [[{ organization_id: id(90) }, "cashier"], [{ restaurant_id: id(91) }, "cashier"],
    [{ device_id: OTHER_DEVICE }, "cashier"], [{ organization_id: id(90) }, "manager"], [{ restaurant_id: id(91) }, "manager"],
    [{ restaurant_id: id(91) }, "restaurant_owner"], [{ restaurant_id: id(91) }, "org_owner"]]) {
    const w = world({ rpc: scripted("unknown", "test", {
      card_attempt_context: contextOk({ role, attempt: contextAttempt("unknown") }),
      card_attempt_adapter_read: adapterRead("unknown", "test", patch) }), provider: { lookup: found() } });
    const out = await w.run(statusInput());
    assert.equal(out.status, 503, JSON.stringify(patch));
    assert.deepEqual(w.calls.provider, []);
    assert.equal(finishOf(w).length, 0);
  }
});

test("an absent or invalid configuration is passed as empty maps; SQL refuses a provider-bound attempt", async () => {
  for (const config of [undefined, "{}", "not json"]) {
    const w = world({ env: { POS_CARD_PROVIDER_CONFIG: config }, rpc: scripted("sent", "test", {
      card_attempt_adapter_read: { ok: false, error: "provider_unavailable", attempt_id: ATTEMPT, attempt_state: "sent" } }),
    provider: { lookup: found() } });
    const out = await w.run(statusInput());
    assert.equal(out.status, 503);
    const read = w.calls.rpc.find((call) => call.name === "card_attempt_adapter_read");
    assert.equal(read.body.p_environment, null);
    assert.deepEqual(read.body.p_terminals, {});
    assert.deepEqual(read.body.p_credentials, {});
    assert.deepEqual(w.calls.provider, []);
  }
});

test("resolved, approved and declined attempts answer their envelope with zero provider calls", async () => {
  for (const [state, extra] of [["unknown", { resolution: "test_closed", classification: "test_unknown" }],
    ["released", { resolution: "test_closed" }], ["sent", { resolution: "test_closed" }], ["approved", {}], ["declined", {}]]) {
    const read = { ...adapterRead(state, "test"), ...extra };
    const w = world({ rpc: scripted(state, "test", { card_attempt_adapter_read: read }), provider: { lookup: found() } });
    const out = await w.run(statusInput({ source: "operator" }));
    assert.equal(out.status, 200);
    assert.equal(out.body.state, state);
    if (extra.resolution) assert.equal(out.body.resolution, extra.resolution);
    assert.deepEqual(w.calls.provider, []);
    assert.equal(finishOf(w).length, 0);
  }
});

test("the recording-refused report needs no configuration secret and no wire profile", async () => {
  const marked = envelope("approved", { mode: "live", classification: "approved_unrecorded", refusal_code: "permission_denied",
    recoverable: true, resume_count: 0 });
  const w = world({ env: { POS_CARD_PROVIDER_CONFIG: undefined, POS_CARD_PAYMENTS_ENABLED: undefined }, profile: null,
    rpc: scripted("approved", "live", { card_attempt_mark_recording_result: marked,
      card_attempt_adapter_read: adapterRead("approved", "live") }) });
  const out = await w.run(statusInput({ recording_refused: true, refusal_code: "permission_denied" }));
  assert.equal(out.status, 200);
  assert.deepEqual(out.body, marked);
  const mark = w.calls.rpc.find((call) => call.name === "card_attempt_mark_recording_result");
  assert.deepEqual(mark.body, { p_pin_session_id: PIN, p_device_id: DEVICE, p_device_session_token: TOKEN,
    p_attempt_id: ATTEMPT, p_refusal_code: "permission_denied", p_caller_auth_user_id: CALLER });
  assert.deepEqual(w.calls.provider, []);
  // Ignored for an attempt that is not approved: the normal status answer.
  const other = world({ env: LIVE_ENV, rpc: scripted("unknown", "live"), provider: { lookup: found({ SynStatus: "S1" }) } });
  await other.run(statusInput({ recording_refused: true, refusal_code: "conflict" }));
  assert.ok(!other.rpcNames().includes("card_attempt_mark_recording_result"));
  const refused = world({ rpc: scripted("approved", "live", { card_attempt_adapter_read: adapterRead("approved", "live"),
    card_attempt_mark_recording_result: { ok: false, error: "precondition_failed", detail: "no_recording_attempt",
      attempt_id: ATTEMPT, attempt_state: "approved" } }) });
  assert.deepEqual((await refused.run(statusInput({ recording_refused: true, refusal_code: "conflict" }))).body,
    { ok: false, error: "precondition_failed", detail: "no_recording_attempt", attempt_id: ATTEMPT, attempt_state: "approved" });
});

test("lookup outcome mapping: an unreadable or unlisted status first (D-063), then not-found / pending, the charge-bearing statuses, approval, decline", async () => {
  const zwsp = String.fromCodePoint(0x200b);
  const cases = [
    [found(), "approved", null],
    [found({ SynStatus: "S2" }), "approved", null],
    [found({ SynAmount: 12.34 }), "approved", null], // a raw number token, kept as its text
    [found({ SynStatus: "S1", SynApproval: "D1" }), "anomaly", "out_of_contract"], // contradictory reply
    [found({ SynStatus: "S3", SynApproval: "D1" }), "anomaly", "voided"],
    [found({ SynStatus: "S4", SynApproval: "D1" }), "anomaly", "refunded"],
    [found({ SynStatus: "S6", SynApproval: "D1" }), "anomaly", "partial_refund"],
    [found({ SynStatus: "S9", SynApproval: "D1" }), "anomaly", "preauthorization"],
    [found({ SynStatus: "S3" }), "anomaly", "voided"],
    [found({ SynStatus: "S7" }), "anomaly", "out_of_contract"], // a status outside every list, no decline
    // DECISION D-063 (superseding LA-2): a declined type beside a status in no list never declines.
    // The amounts below are number tokens (D-064; JSON-string amounts are refused, see the inbound provider money test).
    [{ SynError: true, SynReturn: -7, SynStatus: "S7", SynApproval: "D1", SynAmount: numberToken("12.34"), SynCurrency: 1 }, "anomaly",
      "out_of_contract"],
    [{ SynStatus: "0", SynApproval: "D2" }, "anomaly", "out_of_contract"],
    [{ SynStatus: "S7", SynApproval: "D1", SynAmount: "12.3" }, "anomaly", "out_of_contract"], // a failing essential field
    [found({ SynStatus: `S1${zwsp}` }), "anomaly", "out_of_contract"], // the result field itself is unreadable
    [found({ SynStatus: true }), "anomaly", "out_of_contract"],
    [found({ SynAmount: "12.3" }), "anomaly", "out_of_contract"],
    [found({ SynTip: "1.x" }), "anomaly", "out_of_contract"],
    [found({ SynStatus: "S3", SynAmount: "bad" }), "anomaly", "out_of_contract"],
    [{ SynError: true, SynReturn: -7, SynApproval: "D2" }, "declined", null], // a decline without a status
    [{ SynError: true, SynReturn: -7, SynApproval: "D2", SynAmount: "bad" }, "anomaly", "out_of_contract"],
    [{ SynError: false, SynReturn: 0, SynApproval: "A1", SynAmount: numberToken("12.34"), SynCurrency: 1 }, "anomaly", "out_of_contract"],
    [{ SynError: false, SynReturn: 0, SynApproval: `A1${zwsp}` }, "anomaly", "out_of_contract"],
    [{ SynError: false, SynReturn: 0, SynAmount: numberToken("12.34") }, "anomaly", "out_of_contract"], // a transaction, no status
    // A readable not-found or pending reply leaves the attempt unchanged, whatever else it carries (section 4.55.5).
    [{ SynError: true, SynReturn: -404 }, "not_found", null],
    [{ SynError: true, SynReturn: -404, SynAmount: numberToken("12.34") }, "not_found", null],
    [{ SynError: true, SynReturn: -404, SynAmount: "12.3" }, "not_found", null], // the failing amount is only dropped
    [{ SynError: true, SynReturn: -404, SynAmount: 0 }, "not_found", null],
    [{ SynError: true, SynReturn: -404, SynCurrency: "bad" }, "not_found", null],
    [{ SynError: true, SynReturn: -404, SynApproval: "D1" }, "not_found", null], // never a decline from a not-found reply
    [{ SynError: false, SynReturn: -102 }, "pending", null],
    [{ SynError: false, SynReturn: -102, SynAmount: numberToken("12.34"), SynCurrency: 1 }, "pending", null],
    [{ SynError: false, SynReturn: -102, SynStatus: "S5" }, "pending", null], // a pending status value
    [{ SynStatus: "S5", SynApproval: "A1", SynAmount: numberToken("12.34") }, "pending", null],
    [{ SynError: true, SynReturn: -404, SynStatus: "S0" }, "not_found", null],
    [{ SynStatus: "S0", SynApproval: "D1" }, "not_found", null],
    // DECISION D-063 (superseding V1-1): a status in no list is out of contract before a not-found / pending return code.
    [{ SynError: false, SynReturn: -102, SynStatus: "S7", SynApproval: "D1" }, "anomaly", "out_of_contract"],
    [{ SynError: true, SynReturn: -404, SynStatus: "0", SynApproval: "D1" }, "anomaly", "out_of_contract"],
    [{ SynError: false, SynReturn: -102, SynStatus: "S7" }, "anomaly", "out_of_contract"],
    // An error reply whose currency or flags alone are unreadable reports no transaction.
    [{ SynError: true, SynReturn: -77, SynCurrency: 0 }, "failed", null],
    [{ SynError: "yes", SynReturn: -77 }, "failed", null],
    [{ SynError: true, SynReturn: -77 }, "failed", null],
    [{}, "failed", null],
  ];
  for (const [reply, outcome, anomaly] of cases) {
    const label = JSON.stringify(reply).replaceAll(zwsp, "<U+200B>");
    const body = await lookupOutcome(reply);
    assert.equal(body.p_outcome, outcome, label);
    assert.equal(body.p_provider_fields.anomaly_code ?? null, anomaly, label);
    if (outcome === "approved") {
      assert.equal(body.p_provider_fields.provider_amount, "12.34");
      assert.equal(body.p_provider_fields.provider_currency, "ILS");
    }
    if (["not_found", "pending"].includes(outcome)) assert.ok(!("anomaly_code" in body.p_provider_fields), label);
  }
  // A reference is non-essential: it never decides, in LIVE (read) as in TEST (not read).
  for (const mode of ["test", "live"]) {
    for (const reply of [{ SynError: true, SynReturn: -404, SynReference: "SYN-REF-9" }, { SynError: true, SynReturn: -404, SynVoucher: "V 1" }]) {
      assert.equal((await lookupOutcome(reply, mode)).p_outcome, "not_found", `${mode} ${JSON.stringify(reply)}`);
    }
    assert.equal((await lookupOutcome({ SynError: false, SynReturn: 0, SynReference: "SYN-REF-9" }, mode)).p_outcome, "failed", mode);
  }
  // LIVE drops a failing reference; it never reaches the finish.
  const live = await lookupOutcome({ SynError: true, SynReturn: -404, SynVoucher: "V 1" }, "live");
  assert.ok(!("voucher_number" in live.p_provider_fields));
});

test("every unreadable essential field on a found lookup is the out_of_contract anomaly (G1 vectors)", async () => {
  for (const [field, value] of [["SynError", "false"], ["SynReturn", "0"], ["SynApproval", "A1\u200b"], ["SynPhone", "no"],
    ["SynAmount", "1e3"], ["SynCurrency", "ILSX"], ["SynTip", "0.0"]]) {
    const body = await lookupOutcome(found({ [field]: value }));
    assert.equal(body.p_outcome, "anomaly", field);
    assert.equal(body.p_provider_fields.anomaly_code, "out_of_contract", field);
  }
});

test("no provider fact: transport failures, HTTP errors and unreadable bodies are a failed lookup (stamped only)", async () => {
  for (const reply of [() => { throw new TypeError("network"); }, new Response("{}", { status: 500 }),
    new Response("<html/>", { status: 503 }), new Response("not json", { status: 200 }), new Response("[]", { status: 200 }),
    new Response("<html>maintenance</html>", { status: 200 })]) {
    const body = await lookupOutcome(reply instanceof Response ? () => reply.clone() : reply);
    assert.equal(body.p_outcome, "failed");
    assert.deepEqual(body.p_provider_fields, {});
  }
  // RFC 8259 lets a reader ignore a leading byte-order mark in the provider's reply.
  const bom = await lookupOutcome(() => new Response(`\ufeff${JSON.stringify(found())}`, { status: 200 }));
  assert.equal(bom.p_outcome, "approved");
});

test("inbound provider money (D-064): only a number token with 0-2 fraction digits reaches the finish, as its canonical lexeme", async () => {
  // [raw number token, the canonical lexeme the finish receives; SQL converts and compares it]
  const accepted = [["12.34", "12.34"], ["0.01", "0.01"], ["999999999.99", "999999999.99"], ["12", "12.00"], ["12.3", "12.30"],
    ["12.30", "12.30"], ["0", "0.00"]];
  const refused = ["12.3", "012.34", "1e3", "-1.00", "1,234.00", " 12.34", "12.34 ", "12.340", "1234", "+12.34", "\u0661\u0662.\u0663\u0664",
    "1000000000.00", "0x1.00", "12.34\u00a0"];
  for (const [token, lexeme] of accepted) {
    const body = await lookupOutcome(found({ SynAmount: numberToken(token) }));
    assert.equal(body.p_outcome, "approved", token);
    assert.equal(body.p_provider_fields.provider_amount, lexeme, token);
  }
  // Every JSON string is refused - a well-formed lexeme as well (the former accepted strings) - like every other form.
  for (const amount of [...refused, ...accepted.map(([token]) => token)]) {
    const body = await lookupOutcome(found({ SynAmount: amount }));
    assert.equal(body.p_outcome, "anomaly", amount);
    assert.ok(!("provider_amount" in body.p_provider_fields), amount);
    assert.deepEqual(body.p_provider_fields.dropped_fields, [{ field: "provider_amount", rule: "format" }], amount);
  }
  for (const token of ["1e3", "12.340", "-1.00", "12.345", "1000000000", "-0"]) { // raw number tokens: never a parsed float
    const body = await lookupOutcome(() => new Response(
      `{"SynError":false,"SynReturn":0,"SynStatus":"S1","SynAmount":${token},"SynCurrency":1}`, { status: 200 }));
    assert.equal(body.p_outcome, "anomaly", token);
    assert.deepEqual(body.p_provider_fields.dropped_fields, [{ field: "provider_amount", rule: "format" }], token);
  }
});

test("the lookup uses the attempt's FROZEN references and the STORED key, whatever the current mapping", async () => {
  const rotated = providerConfig({ terminals: { ...providerConfig().terminals, "pad-new": { credential_ref: "cred-new", pinpad_id: "SYNPAD9" } },
    credentials: { ...providerConfig().credentials, "cred-new": { mode: "test", scope: "development",
      secret: { terminal: "SYNROTATED", password: "SYNPASS-NEW" } } } });
  const w = world({ env: { POS_CARD_PROVIDER_CONFIG: JSON.stringify(rotated) }, rpc: scripted(), provider: { lookup: found() } });
  await w.run(statusInput());
  assert.equal(w.calls.provider[0].body.syn_terminal, "SYNTERM");
  assert.equal(w.calls.provider[0].body.syn_query, QUERY_KEY);
  // A manager acting on another device's attempt: the scope-bound finish addresses that attempt's device.
  const manager = world({ rpc: scripted("unknown", "test", {
    card_attempt_context: contextOk({ role: "manager", attempt: contextAttempt("unknown", "test", { own_device: false }) }),
    card_attempt_adapter_read: adapterRead("unknown", "test", { device_id: OTHER_DEVICE }) }), provider: { lookup: found() } });
  await manager.run(statusInput());
  assert.equal(finishOf(manager)[0].body.p_device_id, OTHER_DEVICE);
  assert.equal(manager.calls.provider.length, 1);
});

test("only the attempt's OWN records matter: an unrelated incomplete record never blocks its lookup", async () => {
  const unrelated = providerConfig({ credentials: { ...providerConfig().credentials,
    "cred-other": { mode: "live", scope: "merchant", restaurant_id: id(77), secret: { terminal: "SYNOTHER" } } } });
  const ok = world({ env: { POS_CARD_PROVIDER_CONFIG: JSON.stringify(unrelated) }, rpc: scripted(), provider: { lookup: found() } });
  await ok.run(statusInput({ source: "operator" }));
  assert.equal(ok.calls.provider.length, 1);
  const own = providerConfig({ credentials: { ...providerConfig().credentials,
    "cred-test": { mode: "test", scope: "development", secret: { terminal: "SYNTERM" } } } });
  const blocked_ = world({ env: { POS_CARD_PROVIDER_CONFIG: JSON.stringify(own) }, rpc: scripted(), provider: { lookup: found() } });
  const out = await blocked_.run(statusInput());
  assert.deepEqual(out.body, { ok: false, error: "provider_unavailable", attempt_id: ATTEMPT, attempt_state: "unknown" });
  assert.deepEqual(blocked_.calls.provider, []);
  assert.equal(finishOf(blocked_).length, 0);
});

test("poll cap: a cashier's automatic polling stops at the cap; operator and manager+ calls never get poll_limit", async () => {
  const at = (count, extra = {}) => world({ rpc: scripted("unknown", "test", {
    card_attempt_adapter_read: adapterRead("unknown", "test", { auto_poll_count: count }), ...extra }), provider: { lookup: found() } });
  const capped = at(90);
  const out = await capped.run(statusInput());
  assert.deepEqual(out.body, { ok: false, error: "poll_limit", attempt_id: ATTEMPT, attempt_state: "unknown" });
  assert.deepEqual(capped.calls.provider, []);
  assert.deepEqual(capped.rpcNames(), ["card_attempt_context", "card_attempt_adapter_read"]);
  const below = at(89);
  await below.run(statusInput());
  assert.equal(below.calls.provider.length, 1);
  const operator = at(400);
  await operator.run(statusInput({ source: "operator" }));
  assert.equal(operator.calls.provider.length, 1);
  assert.equal(finishOf(operator)[0].body.p_poll_source, "operator");
  for (const role of ["manager", "restaurant_owner", "org_owner"]) {
    const manager = at(400, { card_attempt_context: contextOk({ role, attempt: contextAttempt("unknown") }) });
    await manager.run(statusInput());
    assert.equal(manager.calls.provider.length, 1, role);
  }
});

test("cadence: any status inside the minimum interval answers the stored envelope with no provider call or write", async () => {
  const at = (lastLookup, extra = {}, role = "cashier") => {
    const w = world({ rpc: scripted("unknown", "test", {
      card_attempt_context: contextOk({ role, attempt: contextAttempt("unknown") }),
      card_attempt_adapter_read: adapterRead("unknown", "test", {
        last_lookup_at: lastLookup, server_ts: "2026-10-27T10:00:10.000000+00:00" }) }), provider: { lookup: found() } });
    return w.run(statusInput(extra)).then((out) => ({ w, out }));
  };
  for (const [extra, role] of [[{}, "cashier"], [{ source: "operator" }, "cashier"], [{}, "manager"]]) {
    const inside = await at("2026-10-27T10:00:08.500000+00:00", extra, role);
    assert.equal(inside.out.body.state, "unknown", JSON.stringify(extra));
    assert.deepEqual(inside.w.calls.provider, []);
    assert.equal(finishOf(inside.w).length, 0);
  }
  assert.equal((await at("2026-10-27T10:00:07.000000+00:00")).w.calls.provider.length, 1);
  assert.equal((await at("2026-10-27T10:00:07.000000+00:00", { source: "operator" })).w.calls.provider.length, 1);
  const bad = await at("yesterday");
  assert.equal(bad.out.status, 503);
  assert.deepEqual(bad.w.calls.provider, []);
});

test("no wire profile, or a configuration that cannot feed it: provider_unavailable with no lookup and no write", async () => {
  const none = world({ profile: null, rpc: scripted(), provider: { lookup: found() } });
  const out = await none.run(statusInput());
  assert.equal(out.status, 503);
  assert.deepEqual(out.body, { ok: false, error: "provider_unavailable", attempt_id: ATTEMPT, attempt_state: "unknown" });
  assert.deepEqual(none.calls.provider, []);
  assert.equal(finishOf(none).length, 0);
  // A LIVE attempt under a 'test' configuration environment (SQL refuses it first; the adapter re-checks).
  const mismatch = world({ rpc: scripted("unknown", "live"), provider: { lookup: found() } });
  assert.equal((await mismatch.run(statusInput())).status, 503);
  assert.deepEqual(mismatch.calls.provider, []);
});

test("the kill switch gates start only: status keeps recovering an in-flight attempt with the flag off", async () => {
  for (const flag of [undefined, "false"]) {
    const w = world({ env: { POS_CARD_PAYMENTS_ENABLED: flag }, rpc: scripted(), provider: { lookup: found() } });
    const out = await w.run(statusInput());
    assert.equal(out.status, 200);
    assert.equal(w.calls.provider.length, 1);
    assert.equal(finishOf(w)[0].body.p_outcome, "approved");
  }
});

test("typed finish answers after a lookup are unavailable or the resolved envelope; nothing is retried", async () => {
  for (const [finish, status] of [[new Response("{}", { status: 500 }), 503],
    [{ ok: false, error: "conflict", detail: "attempt_scope_mismatch" }, 503], [{ ok: false, error: "attempt_not_found" }, 503],
    [envelope("unknown", { resolution: "test_closed" }), 200]]) {
    const w = world({ rpc: scripted("unknown", "test", { card_attempt_finish: finish instanceof Response ? () => finish.clone() : finish }),
      provider: { lookup: found() } });
    const out = await w.run(statusInput());
    assert.equal(out.status, status);
    assert.deepEqual(out.body, status === 503 ? { ok: false, error: "unavailable" } : envelope("unknown", { resolution: "test_closed" }));
    assert.equal(w.calls.provider.length, 1);
    assert.equal(finishOf(w).length, 1);
    assert.ok(!out.text.includes("attempt_scope_mismatch"));
  }
});

test("an absent or unreadable stamp fails closed; a stamp ahead of the database clock never suppresses a lookup", async () => {
  const read = (extra) => adapterRead("unknown", "test", { server_ts: "2026-10-27T10:00:10.000000+00:00", ...extra });
  const absent = read({});
  delete absent.last_lookup_at;
  for (const [answer, label] of [[absent, "absent key"], [read({ last_lookup_at: "yesterday" }), "unreadable"],
    [read({ last_lookup_at: 7 }), "not text"]]) {
    for (const source of ["auto", "operator"]) {
      const w = world({ rpc: scripted("unknown", "test", { card_attempt_adapter_read: answer }), provider: { lookup: found() } });
      const out = await w.run(statusInput({ source }));
      assert.equal(out.status, 503, `${label} ${source}`);
      assert.deepEqual(out.body, { ok: false, error: "unavailable" });
      assert.deepEqual(w.calls.provider, []);
      assert.equal(finishOf(w).length, 0);
    }
  }
  for (const source of ["auto", "operator"]) {
    const ahead = world({ rpc: scripted("unknown", "test", { card_attempt_adapter_read: read({
      last_lookup_at: "2026-10-27T11:00:10.000000+00:00" }) }), provider: { lookup: found() } });
    await ahead.run(statusInput({ source }));
    assert.equal(ahead.calls.provider.length, 1, `a clock stepped back never suppresses a ${source} lookup`);
  }
});

test("a credential of another mode behind the attempt's own terminal: provider_unavailable with no lookup", async () => {
  const other = providerConfig({ credentials: { ...providerConfig().credentials,
    "cred-test": { mode: "live", scope: "merchant", restaurant_id: REST, secret: { terminal: "SYNTERM", password: "SYNPASS-TEST" } } } });
  const w = world({ env: { POS_CARD_PROVIDER_CONFIG: JSON.stringify(other) }, rpc: scripted(), provider: { lookup: found() } });
  const out = await w.run(statusInput({ source: "operator" }));
  assert.deepEqual(out.body, { ok: false, error: "provider_unavailable", attempt_id: ATTEMPT, attempt_state: "unknown" });
  assert.deepEqual(w.calls.provider, []);
  assert.equal(finishOf(w).length, 0);
});

test("an approved attempt answers its envelope under a configuration that can no longer serve its references", async () => {
  const repointed = providerConfig({ terminals: { "pad-x": { credential_ref: "cred-x", pinpad_id: "SYNPADX" } },
    credentials: { "cred-x": { mode: "test", scope: "development", secret: { terminal: "SYNX", password: "SYNPASS-X" } } } });
  for (const config of [JSON.stringify(repointed), undefined]) {
    const w = world({ env: { POS_CARD_PROVIDER_CONFIG: config }, rpc: scripted("approved", "test", {
      card_attempt_context: contextOk({ attempt: contextAttempt("approved") }) }), provider: { lookup: found() } });
    const out = await w.run(statusInput());
    assert.equal(out.status, 200);
    assert.deepEqual(out.body, envelope("approved"));
    assert.deepEqual(w.calls.provider, []);
    assert.deepEqual(w.rpcNames(), ["card_attempt_context", "card_attempt_adapter_read"]);
  }
});
