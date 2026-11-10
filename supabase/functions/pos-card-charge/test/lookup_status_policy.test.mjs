// DECISION D-063 (BIZBOT-PAYMENTS-ZCREDIT-PILOT-001E-W1-LOOKUP-SAFETY-001): after extraction and the status
// normalization, a PRESENT lookup status that is unreadable or in none of the profile's status lists is the
// out_of_contract anomaly before any approval-type or return-code fallback can override it; an ABSENT status (no key,
// JSON null or a blank string - the existing absent rule) keeps the documented absent-status paths. Every expectation
// is a literal, never derived from the engine's own reader or classifier. Scripted RPC tests (a fake provider and a
// fake PostgREST), not PostgreSQL integration tests: the SQL side of the anomaly finish is the accepted 001D / G1
// pgTAP evidence (field-rules lane FR-104 to FR-106, FR-140, FR-142 to FR-145; test-isolation lane TI-58; G1 lane
// G1-028, G1-050, G1-072, G1-075), which this file does not re-run.
import "./no_network.mjs";
import test from "node:test";
import assert from "node:assert/strict";
import { adapterRead, blocked, contextAttempt, contextOk, envelope, LIVE_ENV, numberToken, settleAll, statusInput,
  stray, SYNTHETIC_PROFILE, world } from "./fixtures.mjs";
import { classifyLookup, extractReply, validateProfile } from "../lib/provider/engine.mjs";
import { parseJson, stringifyJson } from "../lib/json.mjs";

test.after(async () => { await settleAll(); assert.deepEqual(blocked, []); assert.deepEqual(stray, []); });

const profile = validateProfile(SYNTHETIC_PROFILE);
/** The classifier's answer for one reply, as JSON (number tokens as JSON numbers). */
function classify(reply, mode = "live") {
  const out = classifyLookup(profile, extractReply(profile, parseJson(JSON.stringify(reply)), { mode }));
  return { outcome: out.outcome, fields: JSON.parse(stringifyJson(out.fields)) };
}
/** The same for a reply given as JSON text: a number token such as -0 reaches the reader as written (review W1-BT-2). */
function classifyText(text, mode = "live") {
  const out = classifyLookup(profile, extractReply(profile, parseJson(text), { mode }));
  return { outcome: out.outcome, fields: JSON.parse(stringifyJson(out.fields)) };
}
const OOC = { anomaly_code: "out_of_contract", provider_return_class: "unclassified" };
const anomalyOOC = (fields) => ({ outcome: "anomaly", fields: { ...fields, ...OOC } });
const money = { SynError: false, SynReturn: 0, SynAmount: numberToken("12.34"), SynCurrency: 1 }; // a number token (D-064)
const moneyFields = { error_flag: false, provider_return_code: 0, provider_amount: "12.34", provider_currency: "ILS" };
// Synthetic values built at run time: no invisible character or card-shaped literal sits in the source.
const space = String.fromCodePoint(0x20);
const ideographicSpace = String.fromCodePoint(0x3000);
const noBreakSpace = String.fromCodePoint(0xa0);
const bell = String.fromCharCode(7);
const fullwidthS1 = String.fromCodePoint(0xff33, 0xff11); // NFKC maps it to the listed "S1"
const twelveDigits = "0".repeat(12);

// [reply value, the text the adapter forwards]: present, readable statuses in none of the synthetic lists. "0", 0,
// "null" and "-" are not absent (no sentinel is invented); "s1" is not the listed "S1" (the normalization folds no case).
const UNLISTED = [["S7", "S7"], ["0", "0"], [0, "0"], [-7, "-7"], ["null", "null"], ["-", "-"], ["s1", "s1"]];
// [reply value, the rule it fails]: present statuses that fail the field rule.
const UNREADABLE = [["S 1", "charset"], [true, "format"], [`S1${bell}`, "control_character"], ["N/A", "charset"],
  ["S".repeat(17), "length"], [1.5, "format"],
  [false, "format"], [[], "format"], [{}, "format"]]; // other JSON types are present too, never absent (review W1-BT-2)
// Absent statuses: no key, JSON null, the empty string and strings of Space_Separators only (the existing absent rule).
const ABSENT = [["no key", {}], ["JSON null", { SynStatus: null }], ["empty", { SynStatus: "" }], ["one space", { SynStatus: space }],
  ["U+3000", { SynStatus: ideographicSpace }], ["two U+00A0", { SynStatus: noBreakSpace.repeat(2) }]];

test("D-063 direct: a present status in no list is out_of_contract before any declined type or return code", () => {
  for (const [value, text] of UNLISTED) {
    const label = JSON.stringify(value);
    const status = { provider_status_code: text };
    assert.deepEqual(classify({ SynStatus: value, SynApproval: "D1" }), anomalyOOC({ approval_type: "D1", ...status }),
      `${label} + a declined type`);
    assert.deepEqual(classify({ SynStatus: value, SynReturn: -404 }), anomalyOOC({ provider_return_code: -404, ...status }),
      `${label} + the not-found code`);
    assert.deepEqual(classify({ SynStatus: value, SynReturn: -102 }), anomalyOOC({ provider_return_code: -102, ...status }),
      `${label} + the pending code`);
    assert.deepEqual(classify({ SynError: true, SynStatus: value, SynReturn: -404, SynApproval: "D1" }),
      anomalyOOC({ error_flag: true, provider_return_code: -404, approval_type: "D1", ...status }),
      `${label} + the not-found code + a declined type`);
    assert.deepEqual(classify({ ...money, SynStatus: value, SynApproval: "A1", SynTip: numberToken("0.00") }),
      anomalyOOC({ ...moneyFields, approval_type: "A1", tip_amount: "0.00", ...status }),
      `${label} + an approved type and apparently matching money`);
    assert.deepEqual(classify({ SynStatus: value }), anomalyOOC(status), `${label} alone`);
    // Every other field may match a conclusive rule: the status still decides first.
    assert.deepEqual(classify({ SynError: false, SynReturn: -102, SynStatus: value, SynApproval: "D2", SynPhone: false,
      SynTip: numberToken("0.00") }), anomalyOOC({ error_flag: false, provider_return_code: -102, approval_type: "D2",
      phone_authorization: false, tip_amount: "0.00", ...status }), `${label} + every other field matching`);
  }
  // The number token -0 is a present status as well (review W1-BT-2): written as JSON text, which JSON.stringify cannot do.
  const negativeZero = { provider_status_code: "-0" };
  assert.deepEqual(classifyText('{"SynStatus":-0,"SynApproval":"D1"}'), anomalyOOC({ approval_type: "D1", ...negativeZero }),
    "-0 + a declined type");
  assert.deepEqual(classifyText('{"SynStatus":-0,"SynReturn":-404}'), anomalyOOC({ provider_return_code: -404, ...negativeZero }),
    "-0 + the not-found code");
  assert.deepEqual(classifyText('{"SynStatus":-0,"SynReturn":-102}'), anomalyOOC({ provider_return_code: -102, ...negativeZero }),
    "-0 + the pending code");
});

test("D-063 direct: an unreadable status is out_of_contract first, whatever else the reply carries", () => {
  for (const [value, rule] of UNREADABLE) {
    const label = `${JSON.stringify(value)} (${rule})`;
    const read = extractReply(profile, parseJson(JSON.stringify({ SynStatus: value })), { mode: "live" });
    assert.deepEqual(read.failures, [{ field: "provider_status_code", rule }], `${label}: the reader's rule`);
    assert.deepEqual(classify({ SynStatus: value, SynApproval: "D1" }), anomalyOOC({ approval_type: "D1" }), `${label} + a declined type`);
    assert.deepEqual(classify({ SynStatus: value, SynReturn: -404 }), anomalyOOC({ provider_return_code: -404 }),
      `${label} + the not-found code`);
    assert.deepEqual(classify({ SynStatus: value, SynReturn: -102 }), anomalyOOC({ provider_return_code: -102 }),
      `${label} + the pending code`);
    assert.deepEqual(classify({ ...money, SynStatus: value, SynApproval: "A1" }), anomalyOOC({ ...moneyFields, approval_type: "A1" }),
      `${label} + an approved type and matching money`);
    assert.deepEqual(classify({ SynStatus: value }), anomalyOOC({}), `${label} alone`);
  }
});

test("D-063 direct: listed statuses keep their handling (recognized, conflict and anomaly controls)", () => {
  const s = (code) => ({ provider_status_code: code });
  const listedAnomaly = (fields, code) => ({ outcome: "anomaly", fields: { ...fields, anomaly_code: code,
    provider_return_class: "unclassified" } });
  const cases = [
    [{ ...money, SynStatus: "S1" }, { outcome: "approved", fields: { ...moneyFields, ...s("S1"), provider_return_class: "approved" } }],
    [{ ...money, SynStatus: "S2" }, { outcome: "approved", fields: { ...moneyFields, ...s("S2"), provider_return_class: "approved" } }],
    // The normalization trims Space_Separators: the padded value is the listed "S1" (forwarded as read).
    [{ ...money, SynStatus: " S1 " }, { outcome: "approved", fields: { ...moneyFields, ...s(" S1 "), provider_return_class: "approved" } }],
    // ... and NFKC: the full-width form is the listed "S1" too (review W1-BT-3).
    [{ ...money, SynStatus: fullwidthS1 }, { outcome: "approved", fields: { ...moneyFields, ...s(fullwidthS1),
      provider_return_class: "approved" } }],
    [{ ...money, SynStatus: "S1", SynApproval: "D1" }, anomalyOOC({ ...moneyFields, ...s("S1"), approval_type: "D1" })], // the conflict
    [{ ...money, SynStatus: "S1", SynAmount: "12.3" }, anomalyOOC({ error_flag: false, provider_return_code: 0,
      provider_currency: "ILS", ...s("S1") })], // a failing essential field
    [{ SynStatus: "S3", SynApproval: "D1" }, listedAnomaly({ approval_type: "D1", ...s("S3") }, "voided")],
    [{ SynStatus: "S4" }, listedAnomaly(s("S4"), "refunded")],
    [{ SynStatus: "S6", SynApproval: "A1" }, listedAnomaly({ approval_type: "A1", ...s("S6") }, "partial_refund")],
    [{ SynStatus: "S9", SynReturn: -404 }, listedAnomaly({ provider_return_code: -404, ...s("S9") }, "preauthorization")],
    [{ SynStatus: "S3", SynAmount: "x" }, anomalyOOC(s("S3"))], // a listed anomaly with a failing essential field
    [{ SynStatus: "S0", SynApproval: "D1" }, { outcome: "not_found", fields: { approval_type: "D1", ...s("S0"),
      provider_return_class: "not_found" } }],
    [{ SynStatus: "S5", SynApproval: "A1", SynAmount: numberToken("12.34") }, { outcome: "pending", fields: { approval_type: "A1", ...s("S5"),
      provider_amount: "12.34", provider_return_class: "pending" } }],
    // A listed status decides over the return code.
    [{ ...money, SynStatus: "S1", SynReturn: -404 }, { outcome: "approved", fields: { ...moneyFields, provider_return_code: -404,
      ...s("S1"), provider_return_class: "approved" } }],
    [{ SynError: true, SynStatus: "S5", SynReturn: -404 }, { outcome: "pending", fields: { error_flag: true,
      provider_return_code: -404, ...s("S5"), provider_return_class: "pending" } }],
  ];
  for (const [reply, expected] of cases) assert.deepEqual(classify(reply), expected, JSON.stringify(reply));
});

test("D-063 direct: an absent status keeps the documented paths (no key, JSON null and blank strings alike)", () => {
  for (const [label, status] of ABSENT) {
    const c = (reply) => classify({ ...reply, ...status });
    assert.deepEqual(c({ SynError: true, SynReturn: -7, SynApproval: "D2" }), { outcome: "declined", fields: { error_flag: true,
      provider_return_code: -7, approval_type: "D2", provider_return_class: "declined" } }, `${label}: a decline`);
    assert.deepEqual(c({ SynError: true, SynReturn: -404 }), { outcome: "not_found", fields: { error_flag: true,
      provider_return_code: -404, provider_return_class: "not_found" } }, `${label}: not found`);
    assert.deepEqual(c({ SynError: false, SynReturn: -102 }), { outcome: "pending", fields: { error_flag: false,
      provider_return_code: -102, provider_return_class: "pending" } }, `${label}: pending`);
    assert.deepEqual(c({ SynError: true, SynReturn: -404, SynApproval: "D1" }), { outcome: "not_found", fields: { error_flag: true,
      provider_return_code: -404, approval_type: "D1", provider_return_class: "not_found" } }, `${label}: not found beside a decline`);
    assert.deepEqual(c({ SynApproval: "D1", SynAmount: "x" }), anomalyOOC({ approval_type: "D1" }),
      `${label}: a decline with a failing essential field`);
    // A failing essential field that the transaction rule does not read decides too (review W1-BT-1).
    for (const [extra, what] of [[{ SynCurrency: "bad" }, "currency"], [{ SynError: "yes" }, "error flag"],
      [{ SynPhone: "no" }, "phone flag"]]) {
      assert.deepEqual(c({ SynApproval: "D1", ...extra }), anomalyOOC({ approval_type: "D1" }), `${label}: a decline with a failing ${what}`);
    }
    assert.deepEqual(c({ SynError: false, SynReturn: 0, SynApproval: "A1" }), anomalyOOC({ error_flag: false,
      provider_return_code: 0, approval_type: "A1" }), `${label}: a transaction without a status`);
    assert.deepEqual(c({ SynError: true, SynReturn: -77 }), { outcome: "failed", fields: {} }, `${label}: no provider fact`);
  }
});

const finishOf = (w) => w.calls.rpc.filter((call) => call.name === "card_attempt_finish");
/** One status call on an 'unknown' attempt; the scripted finish echoes the outcome's state (not the SQL apply rule). */
async function lookupOnce(mode, reply) {
  const w = world({ ...(mode === "live" ? { env: LIVE_ENV } : {}), rpc: {
    card_attempt_context: contextOk({ attempt: contextAttempt("unknown", mode) }),
    card_attempt_adapter_read: adapterRead("unknown", mode),
    card_attempt_finish: (body) => envelope({ approved: "approved", declined: "declined" }[body.p_outcome] ?? "unknown",
      { mode: body.p_mode }) },
  provider: { lookup: reply } });
  const out = await w.run(statusInput());
  const finishes = finishOf(w);
  assert.equal(finishes.length, 1);
  assert.deepEqual(w.rpcNames(), ["card_attempt_context", "card_attempt_adapter_read", "card_attempt_finish"]);
  assert.deepEqual(w.calls.provider.map((call) => call.op), ["lookup"], "one lookup: no commit, no release, no retry");
  return { out, finish: finishes[0] };
}

test("D-063 handler: the finish the adapter sends for an unknown status is the out_of_contract anomaly (LIVE and TEST)", async () => {
  const cases = [
    [{ SynStatus: "S7", SynApproval: "D1" }, { approval_type: "D1", provider_status_code: "S7", ...OOC }],
    [{ SynError: true, SynStatus: "S7", SynReturn: -404 }, { error_flag: true, provider_return_code: -404,
      provider_status_code: "S7", ...OOC }],
    [{ SynError: false, SynStatus: "S7", SynReturn: -102 }, { error_flag: false, provider_return_code: -102,
      provider_status_code: "S7", ...OOC }],
    [{ ...money, SynStatus: "S7", SynApproval: "A1" }, { ...moneyFields, approval_type: "A1", provider_status_code: "S7", ...OOC }],
    [{ SynStatus: "S7" }, { provider_status_code: "S7", ...OOC }],
    [{ SynStatus: "0", SynReturn: -404, SynApproval: "D2" }, { provider_return_code: -404, approval_type: "D2",
      provider_status_code: "0", ...OOC }],
    [{ SynStatus: 0, SynReturn: -102 }, { provider_return_code: -102, provider_status_code: "0", ...OOC }],
    [{ SynStatus: "S 1", SynApproval: "D1" }, { approval_type: "D1", ...OOC,
      dropped_fields: [{ field: "provider_status_code", rule: "charset" }] }],
    [{ SynStatus: true, SynReturn: -404 }, { provider_return_code: -404, ...OOC,
      dropped_fields: [{ field: "provider_status_code", rule: "format" }] }],
    // Other JSON types are present statuses too, never absent (review W1-BT-2).
    [{ SynStatus: false, SynApproval: "D1" }, { approval_type: "D1", ...OOC,
      dropped_fields: [{ field: "provider_status_code", rule: "format" }] }],
    [{ SynStatus: [], SynReturn: -404 }, { provider_return_code: -404, ...OOC,
      dropped_fields: [{ field: "provider_status_code", rule: "format" }] }],
    [{ SynStatus: {}, SynReturn: -102 }, { provider_return_code: -102, ...OOC,
      dropped_fields: [{ field: "provider_status_code", rule: "format" }] }],
  ];
  for (const mode of ["live", "test"]) {
    for (const [reply, fields] of cases) {
      const label = `${mode} ${JSON.stringify(reply)}`;
      const { out, finish } = await lookupOnce(mode, reply);
      assert.equal(finish.body.p_source, "lookup", label);
      assert.equal(finish.body.p_outcome, "anomaly", label);
      assert.deepEqual(finish.body.p_provider_fields, fields, label);
      assert.equal(out.status, 200, label);
      assert.ok(!["approved", "declined"].includes(out.body.state), `${label}: no silent success or decline`);
    }
    // The number token -0 as raw JSON text (review W1-BT-2): a present status, never absent.
    const { finish } = await lookupOnce(mode, () => new Response('{"SynStatus":-0,"SynApproval":"D1"}', { status: 200 }));
    assert.equal(finish.body.p_outcome, "anomaly", `${mode} -0`);
    assert.deepEqual(finish.body.p_provider_fields, { approval_type: "D1", provider_status_code: "-0", ...OOC }, `${mode} -0`);
  }
});

test("D-063 handler: listed and absent statuses still conclude as before (controls)", async () => {
  const cases = [
    [{ ...money, SynStatus: "S1" }, "approved", { ...moneyFields, provider_status_code: "S1", provider_return_class: "approved" }],
    [{ ...money, SynStatus: "S1", SynApproval: "D1" }, "anomaly", { ...moneyFields, approval_type: "D1",
      provider_status_code: "S1", ...OOC }],
    [{ SynStatus: "S3", SynApproval: "D1" }, "anomaly", { approval_type: "D1", provider_status_code: "S3", anomaly_code: "voided",
      provider_return_class: "unclassified" }],
    [{ SynStatus: "S0", SynApproval: "D1" }, "not_found", { approval_type: "D1", provider_status_code: "S0",
      provider_return_class: "not_found" }],
    [{ SynError: true, SynReturn: -7, SynApproval: "D2" }, "declined", { error_flag: true, provider_return_code: -7,
      approval_type: "D2", provider_return_class: "declined" }],
    [{ SynError: true, SynReturn: -404 }, "not_found", { error_flag: true, provider_return_code: -404,
      provider_return_class: "not_found" }],
    [{ SynError: false, SynReturn: -102 }, "pending", { error_flag: false, provider_return_code: -102,
      provider_return_class: "pending" }],
    [{ SynStatus: "", SynError: true, SynReturn: -404, SynApproval: "D1" }, "not_found", { error_flag: true,
      provider_return_code: -404, approval_type: "D1", provider_return_class: "not_found" }], // a blank status is absent
    // With no status, a decline beside a failing essential field the transaction rule does not read (review W1-BT-1).
    [{ SynApproval: "D1", SynCurrency: "bad" }, "anomaly", { approval_type: "D1", ...OOC,
      dropped_fields: [{ field: "provider_currency", rule: "format" }] }],
    [{ SynApproval: "D1", SynError: "yes" }, "anomaly", { approval_type: "D1", ...OOC,
      dropped_fields: [{ field: "error_flag", rule: "format" }] }],
    [{ SynApproval: "D1", SynPhone: "no" }, "anomaly", { approval_type: "D1", ...OOC,
      dropped_fields: [{ field: "phone_authorization", rule: "format" }] }],
  ];
  for (const mode of ["live", "test"]) {
    for (const [reply, outcome, fields] of cases) {
      const label = `${mode} ${JSON.stringify(reply)}`;
      const { finish } = await lookupOnce(mode, reply);
      assert.equal(finish.body.p_outcome, outcome, label);
      assert.deepEqual(finish.body.p_provider_fields, fields, label);
    }
  }
});

test("D-063 handler: the dropped-field tokens ride the anomaly finish beside an unknown status (D-062 unchanged)", async () => {
  const cases = [
    // [mode, reply, the exact finish fields, the rejected raw values that must not enter the RPC argument]
    ["live", { SynStatus: "S7", SynApproval: "D1", SynVoucher: "V 1" }, { approval_type: "D1", provider_status_code: "S7", ...OOC,
      dropped_fields: [{ field: "voucher_number", rule: "charset" }] }, ["V 1"]],
    ["live", { SynError: true, SynStatus: "S7", SynReturn: -404, SynAmount: "77.7", SynReference: `SYN-${twelveDigits}` },
      { error_flag: true, provider_return_code: -404, provider_status_code: "S7", ...OOC,
        dropped_fields: [{ field: "provider_amount", rule: "format" }, { field: "provider_reference", rule: "digit_run" }] },
      ["77.7", `SYN-${twelveDigits}`]],
    ["live", { SynStatus: "S 1", SynReturn: -102, SynVoucher: "V 1" }, { provider_return_code: -102, ...OOC,
      dropped_fields: [{ field: "provider_status_code", rule: "charset" }, { field: "voucher_number", rule: "charset" }] },
      ["S 1", "V 1"]],
    // TEST never reads the card or provider-reference fields, so the failing voucher leaves no evidence there.
    ["test", { SynStatus: "S7", SynApproval: "D1", SynVoucher: "V 1" }, { approval_type: "D1", provider_status_code: "S7", ...OOC },
      ["V 1"]],
    ["test", { SynStatus: true, SynReturn: -404, SynTip: "0.0" }, { provider_return_code: -404, ...OOC,
      dropped_fields: [{ field: "provider_status_code", rule: "format" }, { field: "tip_amount", rule: "format" }] }, ["0.0"]],
  ];
  for (const [mode, reply, fields, rejected] of cases) {
    const label = `${mode} ${JSON.stringify(reply)}`;
    const { finish } = await lookupOnce(mode, reply);
    assert.equal(finish.body.p_outcome, "anomaly", label);
    assert.deepEqual(finish.body.p_provider_fields, fields, label);
    for (const value of rejected) assert.ok(!finish.raw.includes(value), `${label}: ${JSON.stringify(value)} never enters the RPC argument`);
  }
});

test("D-063 handler: an attempt that already carries an anomaly is never sent a clearing result for an unknown status", async () => {
  // The scripted finish answers as the accepted SQL apply rule documents (FR-104 to FR-106, FR-140, FR-144, FR-145,
  // TI-58): an anomaly keeps the state and the charge risk - a changed code replaces the stored one with a new audit
  // (FR-105), an identical repeat writes none (FR-106) - and only an exact approved / declined result clears it. It is
  // a script, not a PostgreSQL run: what this test proves is the outcome the adapter SENDS.
  const held = { classification: "provider_anomaly", anomaly_code: "refunded" };
  for (const state of ["unknown", "released"]) {
    const run = async (reply) => {
      const w = world({ env: LIVE_ENV, rpc: {
        card_attempt_context: contextOk({ attempt: contextAttempt(state, "live", held) }),
        card_attempt_adapter_read: adapterRead(state, "live", held),
        card_attempt_finish: (body) => (["approved", "declined"].includes(body.p_outcome)
          ? envelope(body.p_outcome, { mode: "live", anomaly_code: "refunded" })
          : envelope(state, { mode: "live", ...held,
            ...(body.p_outcome === "anomaly" ? { anomaly_code: body.p_provider_fields.anomaly_code } : {}) })) },
      provider: { lookup: reply } });
      const out = await w.run(statusInput());
      assert.deepEqual(w.calls.provider.map((call) => call.op), ["lookup"]);
      return { out, finish: finishOf(w)[0] };
    };
    for (const reply of [{ SynStatus: "S7", SynApproval: "D1" }, { SynError: true, SynStatus: "S7", SynReturn: -404, SynApproval: "D2" },
      { ...money, SynStatus: "S7", SynApproval: "A1" }, { ...money, SynStatus: "0", SynApproval: "D1" }, { ...money, SynStatus: "s1" }]) {
      const label = `${state} ${JSON.stringify(reply)}`;
      const { out, finish } = await run(reply);
      assert.equal(finish.body.p_outcome, "anomaly", `${label}: never a clearing approved / declined`);
      assert.equal(finish.body.p_provider_fields.anomaly_code, "out_of_contract", label);
      assert.deepEqual([out.body.state, out.body.classification], [state, "provider_anomaly"], `${label}: the charge risk stands`);
    }
    // Controls: the documented clearing results still reach the finish.
    assert.equal((await run({ ...money, SynStatus: "S1" })).finish.body.p_outcome, "approved", `${state}: a listed approved status`);
    assert.equal((await run({ SynError: true, SynReturn: -7, SynApproval: "D2" })).finish.body.p_outcome, "declined",
      `${state}: an absent status and a declined type`);
  }
});

test("D-063 handler: repeated unknown results stay anomalies - one lookup and one anomaly finish per call, never a commit", async () => {
  const replies = [{ SynStatus: "S7", SynApproval: "D1" }, { SynError: true, SynStatus: "0", SynReturn: -404 },
    { ...money, SynStatus: "S8", SynApproval: "A1" }, { SynStatus: "S7", SynApproval: "D1" },
    { SynStatus: "S7", SynApproval: "D1", SynVoucher: "V 1" }, { SynStatus: "S7", SynApproval: "D1", SynVoucher: "V 1" }];
  const w = world({ env: LIVE_ENV, rpc: {
    card_attempt_context: contextOk({ attempt: contextAttempt("unknown", "live") }),
    card_attempt_adapter_read: adapterRead("unknown", "live"),
    card_attempt_finish: (body) => envelope("unknown", { mode: body.p_mode, classification: "provider_anomaly",
      anomaly_code: "out_of_contract" }) },
  provider: { lookup: [...replies] } });
  for (let i = 0; i < replies.length; i++) {
    const out = await w.run(statusInput({ source: "operator" }));
    assert.equal(out.status, 200, `call ${i + 1}`);
    assert.deepEqual([out.body.state, out.body.classification, out.body.anomaly_code], ["unknown", "provider_anomaly", "out_of_contract"]);
  }
  assert.deepEqual(w.calls.provider.map((call) => call.op), replies.map(() => "lookup"), "one lookup per call, no commit");
  const finishes = finishOf(w).map((call) => call.body);
  assert.deepEqual(finishes.map((body) => [body.p_source, body.p_outcome, body.p_poll_source]),
    replies.map(() => ["lookup", "anomaly", "operator"]));
  const voucher = [{ field: "voucher_number", rule: "charset" }];
  assert.deepEqual(finishes.map((body) => body.p_provider_fields), [
    { approval_type: "D1", provider_status_code: "S7", ...OOC },
    { error_flag: true, provider_return_code: -404, provider_status_code: "0", ...OOC },
    { ...moneyFields, approval_type: "A1", provider_status_code: "S8", ...OOC },
    { approval_type: "D1", provider_status_code: "S7", ...OOC },
    { approval_type: "D1", provider_status_code: "S7", ...OOC, dropped_fields: voucher },
    { approval_type: "D1", provider_status_code: "S7", ...OOC, dropped_fields: voucher }, // identical tokens again
  ]);
});
