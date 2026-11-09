// `start` (API_CONTRACT section 4.55.4): the refusal order, the claim wiring, exactly one commit
// for a fresh claim and none otherwise, the outcome classification, deadlines and late replies.
import "./no_network.mjs";
import test from "node:test";
import assert from "node:assert/strict";
import { ANON, assertCleanProviderRequests, ATTEMPT, blocked, CALLER, contextOk, DEVICE, DUPLICATE_KEY, envelope,
  freshClaim, JWT, later, LIVE_ENV, numberToken, ORDER, ORG, PIN, PROVIDER_BASE, providerConfig, providerReply, QUERY_KEY,
  replayClaim, REST, ROW, SERVICE, settleAll, startLive, startTest, stray, TOKEN, world } from "./fixtures.mjs";

test.after(async () => { await settleAll(); assert.deepEqual(blocked, []); assert.deepEqual(stray, []); });

const finishEcho = (body) => {
  const live = body.p_mode === "live";
  const state = { approved: "approved", declined: "declined", unknown: "unknown", anomaly: "unknown" }[body.p_outcome] ?? "sent";
  return envelope(state, { mode: body.p_mode,
    ...(body.p_outcome === "anomaly" && live ? { classification: "provider_anomaly", anomaly_code: body.p_provider_fields.anomaly_code } : {}),
    ...(state === "approved" && live ? { recoverable: false, resume_count: 0 } : {}) });
};
const scripted = (extra = {}) => ({ card_attempt_context: contextOk(), card_attempt_claim: freshClaim(),
  card_attempt_finish: finishEcho, ...extra });
const finishCalls = (w) => w.calls.rpc.filter((call) => call.name === "card_attempt_finish");
const liveWorld = (options) => world({ env: LIVE_ENV, ...options,
  rpc: { card_attempt_context: contextOk(), card_attempt_claim: freshClaim("live"), card_attempt_finish: finishEcho, ...options.rpc } });

test("step (1): flag, configuration and wire profile refusals precede every database read", async () => {
  const cases = [
    [{ env: { POS_CARD_PAYMENTS_ENABLED: undefined } }, 200, "card_payments_disabled"],
    [{ env: { POS_CARD_PAYMENTS_ENABLED: "TRUE" } }, 200, "card_payments_disabled"],
    [{ env: { POS_CARD_PAYMENTS_ENABLED: "1" } }, 200, "card_payments_disabled"],
    [{ env: { POS_CARD_PAYMENTS_ENABLED: "true " } }, 200, "card_payments_disabled"],
    [{ env: { POS_CARD_PROVIDER_CONFIG: undefined } }, 503, "provider_unavailable"],
    [{ env: { POS_CARD_PROVIDER_CONFIG: "{" } }, 503, "provider_unavailable"],
    [{ env: { POS_CARD_PROVIDER_CONFIG: JSON.stringify(providerConfig({ key_format: "alpha16-l28-v1" })) } }, 503, "provider_unavailable"],
    [{ env: { POS_CARD_PROVIDER_CONFIG: JSON.stringify({ ...providerConfig(), key_format: undefined }) } }, 503, "provider_unavailable"],
    [{ env: { POS_CARD_PROVIDER_CONFIG: JSON.stringify(providerConfig({ base_url: "http://synthetic-provider.test" })) } }, 503, "provider_unavailable"],
    [{ env: { POS_CARD_PROVIDER_CONFIG: JSON.stringify(providerConfig({ extra: 1 })) } }, 503, "provider_unavailable"],
    [{ profile: null }, 503, "provider_unavailable"],
    [{ profile: { version: "broken" } }, 503, "provider_unavailable"],
    [{ env: { POS_CARD_PROVIDER_CONFIG: JSON.stringify(providerConfig({ credentials: {
      "cred-test": { mode: "test", scope: "development", secret: { terminal: "SYNTERM" } } } })) } }, 503, "provider_unavailable"],
  ];
  for (const [options, status, error] of cases) {
    const w = world({ ...options, rpc: scripted() });
    const out = await w.run(startTest());
    assert.equal(out.status, status, JSON.stringify(options).slice(0, 120));
    assert.deepEqual(out.body, { ok: false, error });
    assert.deepEqual(w.calls.rpc, []);
    assert.deepEqual(w.calls.provider, []);
  }
  // A currency the profile cannot encode (a step-(1) extension recorded in the packet): nothing is claimed.
  const w = world({ rpc: scripted() });
  const out = await w.run(startTest({ currency_code: "USD" }));
  assert.deepEqual(out.body, { ok: false, error: "provider_unavailable" });
  assert.deepEqual(w.calls.rpc, []);
});

test("step (2): a refused or unusable context proof stops the request - no service call, no provider call", async () => {
  const cases = [
    [{ ok: false, error: "invalid_session" }, 401, { ok: false, error: "invalid_session" }],
    [{ ok: false, error: "permission_denied" }, 200, { ok: false, error: "permission_denied" }],
    [{ ok: false, error: "invalid_request" }, 400, { ok: false, error: "invalid_request" }],
    [new Response("{}", { status: 401 }), 401, { ok: false, error: "invalid_session" }],
    [new Response("{}", { status: 403 }), 401, { ok: false, error: "invalid_session" }],
    [new Response("{}", { status: 500 }), 503, { ok: false, error: "unavailable" }],
    [new Response("not json", { status: 200 }), 503, { ok: false, error: "unavailable" }],
    [{ ok: false, error: "something_else" }, 503, { ok: false, error: "unavailable" }],
    [contextOk({ device_id: ORDER }), 503, { ok: false, error: "unavailable" }],
    [contextOk({ caller_auth_user_id: null }), 503, { ok: false, error: "unavailable" }],
    [contextOk({ role: "kitchen_staff" }), 503, { ok: false, error: "unavailable" }],
  ];
  for (const [answer, status, body] of cases) {
    const w = world({ rpc: scripted({ card_attempt_context: () => (answer instanceof Response ? answer.clone() : answer) }) });
    const out = await w.run(startTest());
    assert.equal(out.status, status, JSON.stringify(body));
    assert.deepEqual(out.body, body);
    assert.deepEqual(w.rpcNames(), ["card_attempt_context"]);
    assert.deepEqual(w.calls.provider, []);
  }
  const slow = world({ rpc: scripted({ card_attempt_context: later(1000, () => new Response(JSON.stringify(contextOk()))) }) });
  const out = await slow.run(startTest());
  assert.equal(out.status, 503);
  assert.deepEqual(slow.rpcNames(), ["card_attempt_context"]);
});

test("the claim carries the request, the SQL projections, the key format and the SAME request's caller binding", async () => {
  const w = liveWorld({ provider: { commit: providerReply() } });
  const out = await w.run(startLive({ amount_minor: 1234 }));
  assert.equal(out.status, 200);
  const [context, claim] = w.calls.rpc;
  assert.equal(context.name, "card_attempt_context");
  assert.equal(context.headers.apikey, ANON);
  assert.equal(context.headers.Authorization, `Bearer ${JWT}`);
  assert.deepEqual(context.body, { p_pin_session_id: PIN, p_device_id: DEVICE, p_device_session_token: TOKEN,
    p_order_id: null, p_attempt_id: null });
  assert.equal(claim.name, "card_attempt_claim");
  assert.equal(claim.headers.apikey, SERVICE);
  assert.equal(claim.headers.Authorization, `Bearer ${SERVICE}`);
  assert.deepEqual(claim.body, { p_pin_session_id: PIN, p_device_id: DEVICE, p_device_session_token: TOKEN,
    p_attempt_id: ATTEMPT, p_mode: "live", p_amount_minor: 1234, p_currency_code: "ILS", p_order_id: ORDER,
    p_expected_revision: 7, p_environment: "production",
    p_terminals: { "pad-test": "cred-test", "pad-live": "cred-live" },
    p_credentials: { "cred-test": { mode: "test", scope: "development" },
      "cred-live": { mode: "live", scope: "merchant", restaurant_id: REST } },
    p_key_format_version: "alpha16-l24-v1", p_caller_auth_user_id: CALLER });
  assert.match(claim.raw, /"p_amount_minor":1234,/); // a raw integer token, never a string
  for (const call of w.calls.rpc) {
    assert.ok(!call.raw.includes("SYNPASS"), "no credential value reaches SQL");
    assert.ok(!call.raw.includes("SYNPAD"), "no PIN-pad identifier reaches SQL");
    assert.equal(call.init.redirect, "error");
    assert.equal(call.init.cache, "no-store");
  }
  await w.settle();
  assert.equal(w.calls.provider.length, 1);
  assertCleanProviderRequests(assert, w);
  const test_ = world({ rpc: scripted(), provider: { commit: providerReply() } });
  await test_.run(startTest());
  const testClaim = test_.calls.rpc[1].body;
  assert.equal(testClaim.p_order_id, null);
  assert.equal(testClaim.p_expected_revision, null);
  assert.equal(testClaim.p_mode, "test");
  await test_.settle();
});

test("every claim refusal makes zero provider requests and answers the closed refusal", async () => {
  const refusals = [
    [{ ok: false, error: "card_payments_disabled", server_ts: "2026-10-27T10:00:00+00:00" }, 200],
    [{ ok: false, error: "provider_unavailable", server_ts: "2026-10-27T10:00:00+00:00" }, 503],
    [{ ok: false, error: "precondition_failed", detail: "currency_not_supported" }, 200],
    [{ ok: false, error: "precondition_failed", detail: "max_test_amount_exceeded" }, 200],
    [{ ok: false, error: "precondition_failed", detail: "max_live_amount_exceeded" }, 200],
    [{ ok: false, error: "precondition_failed", detail: "no_open_shift" }, 200],
    [{ ok: false, error: "precondition_failed", detail: "no_active_drawer" }, 200],
    [{ ok: false, error: "precondition_failed", detail: "ineligible_order_state" }, 200],
    [{ ok: false, error: "conflict", detail: "identity_in_use" }, 200],
    [{ ok: false, error: "conflict", attempt_id: ATTEMPT, attempt_state: "unknown" }, 200],
    [{ ok: false, error: "conflict" }, 200],
    [{ ok: false, error: "payment_in_progress" }, 200],
    [{ ok: false, error: "order_already_settled" }, 200],
    [{ ok: false, error: "order_not_chargeable" }, 200],
    [{ ok: false, error: "amount_mismatch" }, 200],
    [{ ok: false, error: "permission_denied" }, 200],
    [{ ok: false, error: "invalid_session" }, 401],
    [{ ok: false, error: "invalid_request" }, 400],
  ];
  for (const [refusal, status] of refusals) {
    const w = liveWorld({ rpc: { card_attempt_claim: refusal } });
    const out = await w.run(startLive());
    assert.equal(out.status, status, JSON.stringify(refusal));
    assert.deepEqual(out.body, refusal);
    assert.deepEqual(w.rpcNames(), ["card_attempt_context", "card_attempt_claim"]);
    assert.deepEqual(w.calls.provider, []);
    assert.deepEqual(w.tasks, []);
  }
  const unknownToken = world({ rpc: scripted({ card_attempt_claim: { ok: false, error: "rate_limited" } }) });
  assert.deepEqual((await unknownToken.run(startTest())).body, { ok: false, error: "unavailable" });
  assert.deepEqual(unknownToken.calls.provider, []);
});

test("an idempotent replay and a concurrent loser make ZERO provider requests (commit or lookup)", async () => {
  for (const claim of [replayClaim("sent"), replayClaim("unknown"), replayClaim("approved"), replayClaim("declined"),
    replayClaim("released"), { ...freshClaim(), claim_created: false, replayed: true },
    { ...freshClaim(), claim_created: true, replayed: true }, { ...freshClaim(), claim_created: "true" }]) {
    const w = world({ rpc: scripted({ card_attempt_claim: claim }), provider: { commit: providerReply(), lookup: {} } });
    const out = await w.run(startTest());
    assert.equal(out.status, 200);
    assert.equal(out.body.attempt_id, ATTEMPT);
    assert.equal(out.body.state, claim.state);
    assert.deepEqual(w.calls.provider, [], JSON.stringify(claim).slice(0, 60));
    assert.deepEqual(w.rpcNames(), ["card_attempt_context", "card_attempt_claim"]);
    assert.deepEqual(w.tasks, []);
  }
  // Changed immutable inputs under the same identity: SQL answers conflict, nothing is sent.
  const w = world({ rpc: scripted({ card_attempt_claim: { ok: false, error: "conflict", attempt_id: ATTEMPT, attempt_state: "sent" } }) });
  const out = await w.run(startTest({ amount_minor: 999 }));
  assert.deepEqual(out.body, { ok: false, error: "conflict", attempt_id: ATTEMPT, attempt_state: "sent" });
  assert.deepEqual(w.calls.provider, []);
});

test("a fresh claim makes EXACTLY ONE commit carrying exactly the claim's keys and the raw amount token", async () => {
  const w = world({ rpc: scripted(), provider: { commit: providerReply() } });
  const out = await w.run(startTest());
  await w.settle();
  assert.equal(w.calls.provider.length, 1);
  const [commit] = w.calls.provider;
  assert.equal(commit.url, `${PROVIDER_BASE}/synthetic/commit`);
  assert.equal(commit.raw, `{"syn_terminal":"SYNTERM","syn_password":"SYNPASS-TEST","syn_pad":"PADSYNPAD1","syn_amount":12.34,`
    + `"syn_currency":1,"syn_kind":"regular","syn_installments":1,"syn_present":true,"syn_status_key":"${QUERY_KEY}",`
    + `"syn_duplicate_key":"${DUPLICATE_KEY}"}`);
  assert.equal(commit.init.redirect, "error");
  assertCleanProviderRequests(assert, w);
  assert.equal(finishCalls(w).length, 1);
  const finish = finishCalls(w)[0];
  assert.equal(finish.headers.apikey, SERVICE);
  assert.deepEqual(Object.keys(finish.body).sort(), ["p_amount_minor", "p_attempt_row_id", "p_currency_code", "p_device_id",
    "p_local_operation_id", "p_mode", "p_organization_id", "p_outcome", "p_poll_source", "p_provider_fields", "p_source"]);
  assert.equal(finish.body.p_attempt_row_id, ROW);
  assert.equal(finish.body.p_organization_id, ORG);
  assert.equal(finish.body.p_device_id, DEVICE);
  assert.equal(finish.body.p_local_operation_id, ATTEMPT);
  assert.equal(finish.body.p_mode, "test");
  assert.equal(finish.body.p_amount_minor, 1234);
  assert.equal(finish.body.p_currency_code, "ILS");
  assert.equal(finish.body.p_source, "commit");
  assert.equal(finish.body.p_outcome, "approved");
  assert.equal(finish.body.p_poll_source, null);
  assert.ok(!("p_caller_auth_user_id" in finish.body), "finish carries no caller binding");
  assert.deepEqual(out.body, envelope("approved"));
  assert.equal(w.tasks.length, 1, "the commit continues under waitUntil");
});

test("closed reply model: only allowlisted fields reach the finish; TEST strips card and reference fields", async () => {
  const live = liveWorld({ provider: { commit: providerReply() } });
  await live.run(startLive());
  await live.settle();
  const liveFields = finishCalls(live)[0].body.p_provider_fields;
  assert.deepEqual(liveFields, { error_flag: false, provider_return_code: 0, approval_type: "A1", phone_authorization: false,
    provider_reference: "SYN-REF-1", approval_number: "APPR1", voucher_number: "VCH1", card_last4: "4242",
    card_brand_code: "BR1", pan_entry_mode: "CHIP", payment_method_code: "CARD", provider_saved_at: "2026-10-27T10:00:05Z",
    provider_return_class: "approved" });
  const testWorld = world({ rpc: scripted(), provider: { commit: providerReply() } });
  await testWorld.run(startTest());
  await testWorld.settle();
  assert.deepEqual(finishCalls(testWorld)[0].body.p_provider_fields, { error_flag: false, provider_return_code: 0,
    approval_type: "A1", phone_authorization: false, provider_saved_at: "2026-10-27T10:00:05Z", provider_return_class: "approved" });
  for (const w of [live, testWorld]) {
    const everything = JSON.stringify(w.calls.rpc.map((call) => call.raw));
    for (const unsafe of ["SYNTHETIC-CARD-FIELD", "SYNTHETIC-TOKEN", "SYNTHETIC RECEIPT TEXT", "SYNTHETIC VENDOR MESSAGE",
      "SynCardNumber", "SynToken", "SynReceipt", "SynMessage"]) assert.ok(!everything.includes(unsafe), unsafe);
  }
});

test("commit classification: approval, exact decline, unknown, duplicate, phone authorization and anomalies", async () => {
  const cases = [
    [{}, "approved", undefined, "approved"],
    [{ SynApproval: "A2" }, "approved", undefined, "approved"],
    [{ SynApproval: "D1", SynReturn: 0 }, "declined", undefined, "declined"],
    [{ SynApproval: "D2", SynReturn: -33, SynError: true }, "declined", undefined, "declined"], // approval type outranks the return code
    [{ SynApproval: undefined, SynReturn: -33, SynError: true }, "unknown", undefined, "error"],
    [{ SynReturn: -33 }, "unknown", undefined, "unclassified"], // a non-zero return code without a declined type is UNKNOWN
    [{ SynError: true }, "unknown", undefined, "error"],
    [{ SynApproval: "ZZ" }, "unknown", undefined, "unclassified"],
    [{ SynApproval: undefined }, "unknown", undefined, "unclassified"],
    [{ SynApproval: undefined, SynReturn: -901, SynError: true }, "unknown", undefined, "duplicate"], // lookup path, never a resend
    [{ SynApproval: "D1", SynReturn: -901, SynError: true }, "unknown", undefined, "duplicate"], // a duplicate is never declined
    [{ SynPhone: true }, "unknown", undefined, "phone_authorization"],
    [{ SynPhone: true, SynApproval: "D1" }, "unknown", undefined, "phone_authorization"],
    [{ SynTip: numberToken("0.00") }, "approved", undefined, "approved"], // tips are number tokens (D-064)
    [{ SynTip: numberToken("5.00") }, "anomaly", "amount_mismatch", "approved"],
    [{ SynTip: "5.0" }, "anomaly", "out_of_contract", "unclassified"],
    [{ SynTip: "abc" }, "anomaly", "out_of_contract", "unclassified"],
    [{ SynTip: "5.0", SynApproval: "D1" }, "anomaly", "out_of_contract", "unclassified"], // an unreadable tip outranks everything
  ];
  for (const [patch, outcome, anomaly, returnClass] of cases) {
    const w = world({ rpc: scripted(), provider: { commit: providerReply(patch) } });
    await w.run(startTest());
    await w.settle();
    assert.equal(w.calls.provider.length, 1);
    const [finish] = finishCalls(w);
    assert.equal(finish.body.p_outcome, outcome, JSON.stringify(patch));
    assert.equal(finish.body.p_provider_fields.anomaly_code, anomaly, JSON.stringify(patch));
    assert.equal(finish.body.p_provider_fields.provider_return_class, returnClass, JSON.stringify(patch));
  }
});

test("every unreadable essential field fails a commit closed: UNKNOWN, an unreadable tip the anomaly (G1 vectors)", async () => {
  const unreadable = [
    ["SynError", "false", "error_flag"], ["SynError", 0, "error_flag"],
    ["SynReturn", "0", "provider_return_code"], ["SynReturn", 1.5, "provider_return_code"], ["SynReturn", 1234567, "provider_return_code"],
    ["SynApproval", "A1\u200b", "approval_type"], ["SynApproval", "A".repeat(17), "approval_type"], ["SynApproval", true, "approval_type"],
    ["SynPhone", "false", "phone_authorization"], ["SynPhone", 0, "phone_authorization"],
    ["SynStatus", "S1\u0007", "provider_status_code"],
    ["SynAmount", "12.3", "provider_amount"], ["SynCurrency", "ILSX", "provider_currency"], ["SynCurrency", 2, "provider_currency"],
  ];
  for (const [field, value, key] of unreadable) {
    const w = world({ rpc: scripted(), provider: { commit: providerReply({ [field]: value }) } });
    await w.run(startTest());
    await w.settle();
    const [finish] = finishCalls(w);
    assert.equal(finish.body.p_outcome, "unknown", `${field}=${JSON.stringify(value)}`);
    assert.ok(!(key in finish.body.p_provider_fields), `the failing ${key} is not forwarded`);
  }
});

test("absent, null and blank provider values are absent: no failure, no forwarded field", async () => {
  for (const blank of [null, "", "   ", "\u3000"]) {
    const w = world({ rpc: scripted(), provider: { commit: providerReply({ SynTip: blank, SynSavedAt: blank }) } });
    await w.run(startTest());
    await w.settle();
    const [finish] = finishCalls(w);
    assert.equal(finish.body.p_outcome, "approved", JSON.stringify(blank));
    assert.ok(!("tip_amount" in finish.body.p_provider_fields));
    assert.ok(!("provider_saved_at" in finish.body.p_provider_fields));
  }
  for (const blank of [null, "", " "]) {
    const w = world({ rpc: scripted(), provider: { commit: providerReply({ SynApproval: blank }) } });
    await w.run(startTest());
    await w.settle();
    assert.equal(finishCalls(w)[0].body.p_outcome, "unknown", "an absent approval type never approves");
  }
  const w = world({ rpc: scripted(), provider: { commit: providerReply({ SynTip: "\u200b" }) } });
  await w.run(startTest());
  await w.settle();
  assert.equal(finishCalls(w)[0].body.p_outcome, "anomaly", "a format character is a value, not a blank");
});

test("a failing non-essential field is dropped before the finish and the approval is still classified", async () => {
  const digits = "0".repeat(12);
  const masked = `${"0".repeat(4)}x${"0".repeat(4)}`;
  const truncated = `${"0".repeat(6)}${"-".repeat(6)}${"0".repeat(4)}`;
  const dropped = { SynReference: "provider_reference", SynApprovalNumber: "approval_number", SynVoucher: "voucher_number",
    SynDeposit: "deposit_id", SynLast4: "card_last4", SynBrand: "card_brand_code", SynSavedAt: "provider_saved_at",
    SynEntry: "pan_entry_mode", SynMethod: "payment_method_code" };
  for (const patch of [{ SynReference: `SYN-${digits}` }, { SynApprovalNumber: masked }, { SynVoucher: "V 1" },
    { SynLast4: "424" }, { SynLast4: "42a2" }, { SynBrand: "B".repeat(17) }, { SynSavedAt: "2026-10-27T10:00:05" },
    { SynSavedAt: "now" }, { SynSavedAt: "2026-10-27T10:00:05+05:" }, { SynEntry: "CHIP\u0007" }, { SynMethod: masked },
    { SynReference: truncated }, { SynDeposit: truncated.replace(/-/g, "_").replace(/_/, "-") }]) {
    const w = liveWorld({ provider: { commit: providerReply(patch) } });
    await w.run(startLive());
    await w.settle();
    const [finish] = finishCalls(w);
    assert.equal(finish.body.p_outcome, "approved", JSON.stringify(patch));
    const [key] = Object.keys(patch);
    assert.ok(!(dropped[key] in finish.body.p_provider_fields), `${dropped[key]} must not reach the finish`);
    assert.ok(!Object.values(finish.body.p_provider_fields).includes(patch[key]), "the failing value never enters an RPC argument");
  }
});

test("timeouts, network loss, HTTP errors and late replies leave the attempt UNKNOWN with one finish and no resend", async () => {
  const approvalBody = () => Response.json(providerReply());
  const cases = [
    ["deadline", later(5000, approvalBody)],
    ["network", () => { throw new TypeError("network down"); }],
    ["http 500 with a complete approval body", () => new Response(JSON.stringify(providerReply()), { status: 500 })],
    ["http 302", () => new Response(JSON.stringify(providerReply()), { status: 302, headers: { location: "https://elsewhere.test/" } })],
    ["http 502 html", () => new Response("<html>bad gateway</html>", { status: 502 })],
    ["unreadable 200", () => new Response("not json", { status: 200 })],
    ["duplicate keys", () => new Response('{"SynError":false,"SynError":false}', { status: 200 })],
    ["array", () => new Response("[]", { status: 200 })],
    // A complete approval, padded past the 256 KiB reply cap: unreadable, so UNKNOWN (never approved).
    ["oversized", () => new Response(JSON.stringify(providerReply({ SynPad: "x".repeat(260 * 1024) })), { status: 200 })],
  ];
  for (const [label, reply] of cases) {
    const w = world({ rpc: scripted(), provider: { commit: reply } });
    const out = await w.run(startTest());
    await w.settle();
    assert.equal(w.calls.provider.length, 1, label);
    assert.equal(finishCalls(w).length, 1, label);
    assert.equal(finishCalls(w)[0].body.p_outcome, "unknown", label);
    assert.equal(out.status, 200);
    assert.ok(["sent", "unknown"].includes(out.body.state), label);
  }
});

test("the start answer is not held for the terminal interaction: 'sent' after the window, the commit continues", async () => {
  const w = world({ rpc: scripted(), provider: { commit: later(120, () => Response.json(providerReply())) } });
  const out = await w.run(startTest());
  assert.deepEqual(out.body, envelope("sent"));
  assert.equal(finishCalls(w).length, 0, "the finish has not happened yet when start answers");
  assert.equal(w.tasks.length, 1);
  await w.settle();
  assert.equal(finishCalls(w).length, 1);
  assert.equal(finishCalls(w)[0].body.p_outcome, "approved");
  assert.equal(w.calls.provider.length, 1);
});

test("a late commit reply meeting a row that already left 'sent' changes nothing and causes no extra call", async () => {
  const w = world({ rpc: scripted({ card_attempt_finish: envelope("approved", { mode: "test" }) }),
    provider: { commit: providerReply({ SynApproval: "D1" }) } });
  const out = await w.run(startTest());
  await w.settle();
  assert.deepEqual(out.body, envelope("approved"));
  assert.deepEqual(w.rpcNames(), ["card_attempt_context", "card_attempt_claim", "card_attempt_finish"]);
  assert.equal(w.calls.provider.length, 1);
});

test("typed finish answers (scope mismatch, not found, invalid, a resolved row) end the request: one commit, one finish", async () => {
  const answers = [
    [{ ok: false, error: "conflict", detail: "attempt_scope_mismatch", server_ts: "2026-10-27T10:00:01+00:00" }, envelope("sent")],
    [{ ok: false, error: "attempt_not_found", server_ts: "2026-10-27T10:00:01+00:00" }, envelope("sent")],
    [{ ok: false, error: "invalid_request", server_ts: "2026-10-27T10:00:01+00:00" }, envelope("sent")],
    [envelope("unknown", { resolution: "test_closed" }), envelope("unknown", { resolution: "test_closed" })],
  ];
  for (const [finish, expected] of answers) {
    const w = world({ rpc: scripted({ card_attempt_finish: finish }), provider: { commit: providerReply() } });
    const out = await w.run(startTest());
    await w.settle();
    assert.deepEqual(out.body, expected, JSON.stringify(finish));
    assert.equal(w.calls.provider.length, 1);
    assert.deepEqual(w.rpcNames(), ["card_attempt_context", "card_attempt_claim", "card_attempt_finish"]);
    assert.ok(!out.text.includes("attempt_scope_mismatch"), "no unknown detail token reaches the POS");
  }
});

test("an uncertain claim (RPC failure, timeout or malformed answer) makes no provider call", async () => {
  const cases = [
    [new Response("{}", { status: 500 }), 503], [later(1000, () => Response.json(freshClaim())), 503],
    [() => { throw new TypeError("reset"); }, 503], [new Response("[]"), 503],
    [{ ...freshClaim(), provider_query_key: "short" }, 200], [{ ...freshClaim(), provider_duplicate_key: QUERY_KEY }, 200],
    [{ ...freshClaim(), provider_key_format_version: "alpha16-l20-v1" }, 200], [{ ...freshClaim(), local_operation_id: ORDER }, 200],
    [{ ...freshClaim(), mode: "live" }, 200], [{ ...freshClaim(), amount_minor: 1235 }, 200],
    [{ ...freshClaim(), device_id: ORDER }, 200], [{ ...freshClaim(), organization_id: ORDER }, 200],
    [{ ...freshClaim(), restaurant_id: ORDER }, 200], [{ ...freshClaim(), terminal_ref: "pad-live" }, 200],
    [{ ...freshClaim(), state: "unknown", classification: "test_unknown" }, 200],
  ];
  for (const [index, [claim, status]] of cases.entries()) {
    const w = world({ rpc: scripted({ card_attempt_claim: claim instanceof Response ? () => claim.clone() : claim }),
      provider: { commit: providerReply() } });
    const out = await w.run(startTest());
    assert.deepEqual(w.calls.provider, [], `case ${index}`);
    assert.equal(out.status, status, `case ${index}`);
    if (status === 503) {
      assert.deepEqual(out.body, { ok: false, error: "unavailable" }, `case ${index}`);
    } else {
      // Exactly the claim's own envelope (no adapter fact), answered without a commit.
      const { ok, attempt_id, state, classification, recorded, amount_minor, currency_code, server_ts } = claim;
      assert.deepEqual(out.body, { ok, attempt_id, state, classification, recorded, amount_minor, currency_code, server_ts },
        `case ${index}`);
    }
    assert.deepEqual(w.tasks, [], `case ${index}`);
  }
});

test("a failed finish after the commit is not retried; the POS recovers through status", async () => {
  const w = world({ rpc: scripted({ card_attempt_finish: new Response("{}", { status: 500 }) }),
    provider: { commit: providerReply() } });
  const out = await w.run(startTest());
  await w.settle();
  assert.deepEqual(out.body, envelope("sent"));
  assert.equal(finishCalls(w).length, 1);
  assert.equal(w.calls.provider.length, 1);
});

test("TEST start is order-less and calls only the card RPCs - never a recording or payment writer", async () => {
  const w = world({ rpc: scripted(), provider: { commit: providerReply() } });
  await w.run(startTest());
  await w.settle();
  assert.deepEqual(w.rpcNames(), ["card_attempt_context", "card_attempt_claim", "card_attempt_finish"]);
  for (const call of w.calls.rpc) assert.ok(!/sync_push|record_payment|payment\.create|payments/.test(call.name));
});

test("the finish writes the provider fact even after the PIN session lapsed or a support session started", async () => {
  // card_attempt_finish takes no session proof and no caller binding (D-060 point 4): the adapter
  // never re-proves before it, so a session change between claim and reply cannot discard the fact.
  let sessionValid = true;
  const w = world({ rpc: scripted({
    card_attempt_context: () => (sessionValid ? contextOk() : { ok: false, error: "permission_denied" }),
    card_attempt_claim: () => { sessionValid = false; return freshClaim(); },
  }), provider: { commit: providerReply() } });
  await w.run(startTest());
  await w.settle();
  assert.deepEqual(w.rpcNames(), ["card_attempt_context", "card_attempt_claim", "card_attempt_finish"]);
  assert.equal(finishCalls(w)[0].body.p_outcome, "approved");
});
