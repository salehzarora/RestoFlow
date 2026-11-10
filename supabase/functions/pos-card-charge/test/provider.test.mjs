// The provider engine: the closed wire-profile schema, the closed reply model (a reply is read
// ONLY at the allowlisted names; TEST never reads card or reference fields), the classification
// units against 001D's M2 precedence, the truncated-card pre-filter, and silence (nothing is ever
// logged). Every vendor name and code here is synthetic (fixtures.mjs SYNTHETIC_PROFILE).
import "./no_network.mjs";
import test from "node:test";
import assert from "node:assert/strict";
import { adapterRead, blocked, contextAttempt, contextOk, envelope, freshClaim, numberToken, providerReply, settleAll,
  startTest, statusInput, stray, SYNTHETIC_PROFILE, world } from "./fixtures.mjs";
import { classifyCommit, classifyLookup, classifyRelease, extractReply, ProfileError, secretNames, validateProfile }
  from "../lib/provider/engine.mjs";
import { parseJson } from "../lib/json.mjs";
import { safeTextFailure } from "../lib/text_policy.mjs";

test.after(async () => { await settleAll(); assert.deepEqual(blocked, []); assert.deepEqual(stray, []); });

const clone = (value) => JSON.parse(JSON.stringify(value));
const profile = validateProfile(SYNTHETIC_PROFILE);
/** A string-accepting variant: return codes and booleans may arrive as JSON strings. */
const lenient = validateProfile({ ...clone(SYNTHETIC_PROFILE), reply: { ...clone(SYNTHETIC_PROFILE.reply),
  provider_return_code: { name: "SynReturn", accept: ["number", "string"] }, error_flag: { name: "SynError", accept: ["boolean", "string"] } } });
const reading = (fields, mode = "live", p = profile) => extractReply(p, parseJson(typeof fields === "string" ? fields : JSON.stringify(fields)), { mode });
const commit = (fields, p = profile) => classifyCommit(p, reading(fields, "live", p));
const lookup = (fields, mode = "live") => classifyLookup(profile, reading(fields, mode));
const release = (fields) => classifyRelease(profile, reading(fields));
const ESSENTIAL = ["error_flag", "provider_return_code", "approval_type", "phone_authorization", "provider_status_code",
  "provider_amount", "provider_currency", "tip_amount"];
// A synthetic truncated-card shape for structured fields: 6 + a hyphen / underscore run + 4 (no real value).
const truncated = (run = "---") => `${"0".repeat(6)}${run}${"0".repeat(4)}`;

test("the synthetic profile validates; every structural violation is refused", () => {
  assert.deepEqual([...secretNames(profile)].sort(), ["password", "terminal"]);
  const mutations = [
    (p) => { p.extra = 1; },
    (p) => { p.version = "Bad Version"; },
    (p) => { p.routes.commit = "relative"; },
    (p) => { p.routes.lookup = "/x?y=1"; },
    (p) => { p.routes.release = null; }, // the request list must be null with it
    (p) => { p.request.commit = p.request.commit.filter((spec) => spec.from !== "amount"); },
    (p) => { p.request.commit.push({ name: "syn_amount2", from: "amount" }); },
    (p) => { p.request.commit = p.request.commit.filter((spec) => spec.from !== "duplicate_key"); },
    (p) => { p.request.commit[0].name = p.request.commit[1].name; },
    (p) => { p.request.lookup.push({ name: "syn_amount", from: "amount" }); },
    (p) => { p.request.lookup.push({ name: "syn_dup", from: "duplicate_key" }); },
    (p) => { p.request.release.push({ name: "syn_key", from: "status_key" }); },
    (p) => { p.request.commit = p.request.commit.filter((spec) => spec.from !== "credential"); },
    (p) => { p.request.commit[5].value = { string: "x", integer: "1" }; },
    (p) => { p.request.commit[5].value = { integer: "1.5" }; },
    (p) => { p.request.commit[2].prefix = "PAD X"; },
    (p) => { p.request.commit[0].secret = "Bad-Name"; },
    (p) => { p.request.commit[3].value = { string: "x" }; },
    (p) => { p.request.commit.push({ name: "syn_other", from: "order_id" }); },
    (p) => { p.reply.card_number = { name: "SynCardNumber", accept: ["string"] }; },
    (p) => { p.reply.message = { name: "SynMessage", accept: ["string"] }; },
    (p) => { p.reply.error_flag.accept = ["number"]; },
    (p) => { p.reply.tip_amount.accept = ["boolean"]; },
    (p) => { p.reply.provider_amount.accept = ["string", "string"]; },
    (p) => { p.reply.provider_amount.accept = []; },
    (p) => { p.reply.provider_reference.name = p.reply.approval_number.name; },
    // Review C-3: all eight essential classification inputs must be mapped.
    ...ESSENTIAL.map((key) => (p) => { delete p.reply[key]; }),
    (p) => { p.codes.approval_declined.push("A1"); },
    (p) => { p.codes.status_voided.push("S1"); },
    (p) => { p.codes.status_not_found.push("S1"); },
    (p) => { p.codes.status_pending.push("S3"); },
    (p) => { p.codes.status_preauthorization.push("S6"); },
    (p) => { p.codes.return_duplicate.push("0"); },
    (p) => { p.codes.return_duplicate.push("-404"); },
    (p) => { p.codes.lookup_not_found.push("-102"); },
    // Fact-check B1: the four return-code lists are pairwise disjoint, so a success code never
    // doubles as a not-found or pending lookup code.
    (p) => { p.codes.lookup_not_found.push("0"); },
    (p) => { p.codes.lookup_pending.push("0"); },
    (p) => { p.codes.lookup_pending.push("-901"); },
    (p) => { p.codes.approval_approved = []; },
    (p) => { p.codes.status_approved = []; },
    (p) => { p.codes.return_success = []; },
    // Review C-7: return-code lists hold canonical integers within +-999 999 only.
    (p) => { p.codes.return_success = ["00"]; },
    (p) => { p.codes.return_success = ["-0"]; },
    (p) => { p.codes.return_success = ["+1"]; },
    (p) => { p.codes.return_success = ["1234567"]; },
    (p) => { p.codes.lookup_not_found = ["-0404"]; },
    (p) => { p.codes.lookup_pending = ["P"]; },
    (p) => { p.codes.currency_request.ils = { integer: "1" }; },
    (p) => { p.codes.currency_request = { USD: { integer: "2" } }; }, // only two-decimal ILS is encodable (Q-007 interim)
    (p) => { p.codes.currency_request = { JPY: { integer: "3" } }; },
    (p) => { p.codes.currency_reply["1"] = "ils"; },
    (p) => { p.codes.currency_reply = { 2: "USD" }; },
    (p) => { p.codes.currency_reply = { "x y": "ILS" }; },
    (p) => { delete p.codes.lookup_pending; },
    (p) => { delete p.codes.status_not_found; },
    (p) => { p.codes.extra = []; },
  ];
  for (const [index, mutate] of mutations.entries()) {
    const copy = clone(SYNTHETIC_PROFILE);
    mutate(copy);
    assert.throws(() => validateProfile(copy), ProfileError, `mutation ${index}`);
  }
  const noRelease = clone(SYNTHETIC_PROFILE);
  noRelease.routes.release = null;
  noRelease.request.release = null;
  assert.equal(validateProfile(noRelease).routes.release, null, "a profile without a release route is valid");
});

test("a reply is read ONLY at the allowlisted names; TEST never touches card or reference fields", () => {
  for (const mode of ["live", "test"]) {
    const touched = new Set();
    const reply = new Proxy(parseJson(JSON.stringify(providerReply())), {
      get(target, key) { touched.add(String(key)); return target[key]; },
      getOwnPropertyDescriptor(target, key) { touched.add(String(key)); return Reflect.getOwnPropertyDescriptor(target, key); },
      has(target, key) { touched.add(String(key)); return key in target; },
      ownKeys() { throw new Error("the reply is never enumerated"); },
    });
    extractReply(profile, reply, { mode });
    for (const unsafe of ["SynCardNumber", "SynToken", "SynReceipt", "SynMessage"]) assert.ok(!touched.has(unsafe), `${mode} ${unsafe}`);
    for (const reference of ["SynReference", "SynApprovalNumber", "SynVoucher", "SynDeposit", "SynLast4", "SynBrand", "SynEntry",
      "SynMethod"]) assert.equal(touched.has(reference), mode === "live", `${mode} ${reference}`);
  }
});

test("absent, JSON null and blank values are absent (no value, no failure); a present invalid value fails", () => {
  for (const value of [null, "", "\u3000", " \u00a0 "]) {
    const read = reading(providerReply({ SynReference: value, SynVoucher: value }));
    assert.ok(!("provider_reference" in read.values) && !("voucher_number" in read.values), JSON.stringify(value));
    assert.deepEqual(read.failures, [], JSON.stringify(value));
  }
  assert.ok(!("provider_reference" in reading(providerReply({ SynReference: undefined })).values));
  // Characters that are not Space_Separators - most of them removed by String.prototype.trim - are a value, never a
  // blank (verification V2-4).
  for (const code of [0x09, 0x0a, 0x0b, 0x0c, 0x85, 0x180e, 0xfeff, 0x2028]) {
    const tip = String.fromCodePoint(code);
    assert.equal(commit({ SynError: false, SynReturn: 0, SynApproval: "A1", SynTip: tip }).fields.anomaly_code, "out_of_contract",
      `U+${code.toString(16)}`);
  }
  assert.deepEqual(reading(providerReply({ SynReference: "\u200b" })).failures, [{ field: "provider_reference", rule: "control_character" }]);
  assert.deepEqual(reading(providerReply({ SynVoucher: "V 1" })).failures, [{ field: "voucher_number", rule: "charset" }]);
  assert.deepEqual(reading(providerReply({ SynReference: 7 })).failures, [{ field: "provider_reference", rule: "format" }]);
});

test("commit classification mirrors 001D M2: tip first, essential failures, phone, duplicate, decline, approval", () => {
  const approved = commit({ SynError: false, SynReturn: 0, SynApproval: "A1" });
  assert.equal(approved.outcome, "approved");
  assert.deepEqual(Object.keys(approved.fields), ["error_flag", "provider_return_code", "approval_type", "provider_return_class"]);
  assert.equal(approved.fields.provider_return_code.text, "0", "the canonical integer token");
  assert.equal(approved.fields.provider_return_class, "approved");
  // Amounts and tips are JSON number tokens (DECISION D-064).
  assert.equal(commit({ SynError: false, SynReturn: 0, SynApproval: "A1", SynTip: numberToken("0.00") }).outcome, "approved", "a zero tip");
  assert.equal(commit({ SynError: false, SynReturn: 0, SynApproval: "A1", SynTip: numberToken("0.01") }).fields.anomaly_code,
    "amount_mismatch");
  assert.equal(commit({ SynError: false, SynReturn: 0, SynApproval: "D1", SynTip: "x" }).fields.anomaly_code, "out_of_contract",
    "an unreadable tip is the anomaly whatever else the reply says");
  assert.equal(commit({ SynError: true, SynReturn: 0, SynApproval: "A1" }).outcome, "unknown");
  assert.equal(commit({ SynError: true, SynReturn: 0, SynApproval: "A1" }).fields.provider_return_class, "error");
  assert.equal(commit({ SynError: false, SynReturn: 5, SynApproval: "A1" }).outcome, "unknown");
  assert.equal(commit({ SynError: false, SynApproval: "A1" }).outcome, "unknown", "no return code");
  assert.equal(commit({ SynReturn: 0, SynApproval: "A1" }).outcome, "unknown", "no error flag");
  const phone = commit({ SynError: false, SynReturn: 0, SynApproval: "A1", SynPhone: true });
  assert.deepEqual([phone.outcome, phone.fields.provider_return_class], ["unknown", "phone_authorization"]);
  // Review A2: a duplicate refusal goes to the lookup path even with a declined (or approved) type.
  for (const approval of ["A1", "D1", undefined]) {
    const duplicate = commit({ SynError: false, SynReturn: -901, ...(approval ? { SynApproval: approval } : {}) });
    assert.deepEqual([duplicate.outcome, duplicate.fields.provider_return_class], ["unknown", "duplicate"], String(approval));
  }
  assert.equal(commit({ SynError: true, SynReturn: 3, SynApproval: "D2" }).outcome, "declined", "a declined type declines");
  // Any failing essential field is UNKNOWN (never declined, never approved).
  for (const bad of [{ SynApproval: 5 }, { SynError: "false" }, { SynReturn: "0" }, { SynPhone: "no" }, { SynStatus: "S 1" },
    { SynAmount: "1.0" }, { SynCurrency: "ils" }, { SynApproval: truncated("___") }]) {
    const out = commit({ SynError: false, SynReturn: 0, SynApproval: "A1", ...bad });
    assert.deepEqual([out.outcome, out.fields.provider_return_class], ["unknown", "unclassified"], JSON.stringify(Object.keys(bad)));
  }
  // Review C-7: return codes must be canonical integers, as JSON numbers or (if accepted) strings.
  assert.equal(commit('{"SynError":false,"SynReturn":-0,"SynApproval":"A1"}').outcome, "unknown", "-0");
  assert.equal(commit('{"SynError":false,"SynReturn":0.0,"SynApproval":"A1"}').outcome, "unknown", "0.0");
  assert.equal(commit('{"SynError":false,"SynReturn":0e0,"SynApproval":"A1"}').outcome, "unknown", "0e0");
  assert.equal(commit('{"SynError":false,"SynReturn":1234567,"SynApproval":"A1"}').outcome, "unknown", "seven digits");
  assert.equal(commit({ SynError: "false", SynReturn: "0", SynApproval: "A1" }, lenient).outcome, "approved");
  for (const text of ["-0", "00", "+0", "0.0", "1e0", " 0", "0 ", "-00", "000000"]) {
    assert.equal(commit({ SynError: false, SynReturn: text, SynApproval: "A1" }, lenient).outcome, "unknown", JSON.stringify(text));
  }
  for (const text of ["TRUE", "1", "yes", "", " false"]) {
    assert.equal(commit({ SynError: text, SynReturn: 0, SynApproval: "A1" }, lenient).outcome, "unknown", JSON.stringify(text));
  }
});

test("lookup classification: an unreadable or unlisted status first (D-063), then not-found / pending, the charge-bearing statuses, approval, decline", () => {
  const anomaly = (fields, mode) => { const out = lookup(fields, mode); return out.outcome === "anomaly" ? out.fields.anomaly_code : out.outcome; };
  assert.equal(anomaly({ SynStatus: "S1", SynAmount: numberToken("1.00"), SynCurrency: 1 }), "approved"); // a number token (D-064)
  assert.equal(anomaly({ SynStatus: "S2" }), "approved");
  assert.equal(anomaly({ SynStatus: "S1", SynAmount: "1.0", SynCurrency: 1 }), "out_of_contract", "an unreadable amount");
  // Review C-1: a declined type never overrides a charge-bearing status, and never turns an approval into a decline.
  assert.equal(anomaly({ SynStatus: "S1", SynApproval: "D1" }), "out_of_contract");
  for (const [status, code] of [["S3", "voided"], ["S4", "refunded"], ["S6", "partial_refund"], ["S9", "preauthorization"]]) {
    assert.equal(anomaly({ SynStatus: status }), code);
    assert.equal(anomaly({ SynStatus: status, SynApproval: "D1" }), code, `${status} + a declined type`);
    assert.equal(anomaly({ SynStatus: status, SynAmount: "x" }), "out_of_contract", `${status} + an unreadable amount`);
  }
  // Delta review LA-1: a readable not-found or pending reply is unchanged, whatever it also carries (section 4.55.5).
  assert.deepEqual(lookup({ SynStatus: "S0" }), { outcome: "not_found", fields: { provider_status_code: "S0",
    provider_return_class: "not_found" } });
  assert.equal(anomaly({ SynStatus: "S5" }), "pending");
  for (const extra of [{ SynAmount: "1.00" }, { SynAmount: "1.0" }, { SynAmount: 0 }, { SynApproval: "A1" }, { SynApproval: "D1" },
    { SynApproval: 5 }, { SynReference: "SYN-REF-1" }, { SynVoucher: "V 1" }, { SynCurrency: "ils" }]) {
    for (const [base, outcome] of [[{ SynStatus: "S0" }, "not_found"], [{ SynStatus: "S5" }, "pending"],
      [{ SynReturn: -404 }, "not_found"], [{ SynReturn: -102 }, "pending"]]) {
      const out = lookup({ ...base, ...extra });
      assert.equal(out.outcome, outcome, JSON.stringify({ ...base, ...extra }));
      assert.ok(!("anomaly_code" in out.fields));
    }
  }
  const dropped = lookup({ SynReturn: -404, SynAmount: "1.0" });
  assert.ok(!("provider_amount" in dropped.fields), "a failing amount on a not-found reply is only dropped");
  // DECISION D-063 supersedes delta review LA-2 and verification V1-1: a status in no list is out_of_contract before
  // any declined type or not-found / pending return code is read (only an absent status keeps those paths, below).
  for (const status of ["S7", "0", 0, 7]) {
    assert.equal(anomaly({ SynStatus: status, SynApproval: "D1" }), "out_of_contract", JSON.stringify(status));
    assert.equal(anomaly({ SynStatus: status, SynApproval: "D1", SynAmount: "x" }), "out_of_contract", "with a failing essential field");
    for (const returnCode of [-102, -404]) {
      assert.equal(anomaly({ SynStatus: status, SynReturn: returnCode, SynApproval: "D1" }), "out_of_contract", `${status} ${returnCode} D1`);
      assert.equal(anomaly({ SynStatus: status, SynReturn: returnCode }), "out_of_contract", `${status} ${returnCode}`);
      assert.equal(anomaly({ SynStatus: status, SynReturn: returnCode, SynApproval: "A1", SynAmount: "1.00" }), "out_of_contract");
    }
  }
  // A listed status still decides over those return codes (verification V2-1).
  for (const returnCode of [-102, -404]) {
    assert.equal(anomaly({ SynStatus: "S3", SynReturn: returnCode }), "voided", `S3 ${returnCode}`);
    assert.equal(anomaly({ SynStatus: "S4", SynReturn: returnCode }), "refunded", `S4 ${returnCode}`);
    assert.equal(anomaly({ SynStatus: "S6", SynReturn: returnCode }), "partial_refund", `S6 ${returnCode}`);
    assert.equal(anomaly({ SynStatus: "S9", SynReturn: returnCode }), "preauthorization", `S9 ${returnCode}`);
    // An unreadable status is the anomaly first, even beside these return codes (final verification F1-1).
    for (const unreadable of ["S 1", "S0 X", "N/A", true]) {
      assert.equal(anomaly({ SynStatus: unreadable, SynReturn: returnCode }), "out_of_contract", `${unreadable} ${returnCode}`);
    }
    assert.equal(anomaly({ SynStatus: "S1", SynReturn: returnCode, SynAmount: numberToken("1.00"), SynCurrency: 1 }), "approved",
      `S1 ${returnCode}`);
    assert.equal(anomaly({ SynStatus: "S1", SynReturn: returnCode, SynApproval: "D1" }), "out_of_contract", `S1 ${returnCode} D1`);
    assert.equal(anomaly({ SynStatus: "S0", SynReturn: returnCode === -102 ? -404 : -102 }), "not_found", "S0 decides");
  }
  // Any other status and an unreadable status are out_of_contract.
  assert.equal(anomaly({ SynStatus: "S7" }), "out_of_contract");
  assert.equal(anomaly({ SynStatus: "S7", SynApproval: "A1" }), "out_of_contract");
  assert.equal(anomaly({ SynStatus: "S 1" }), "out_of_contract");
  assert.equal(anomaly({ SynStatus: truncated("___") }), "out_of_contract");
  assert.equal(anomaly({ SynStatus: "S0 X" }), "out_of_contract", "an unreadable not-found status is no readable not-found reply");
  // Without a status (reviews A4 / C-4): a decline declines; a transaction is out_of_contract; a reference never decides.
  assert.equal(anomaly({ SynApproval: "D1" }), "declined");
  assert.equal(anomaly({ SynApproval: "D1", SynAmount: "x" }), "out_of_contract");
  assert.equal(anomaly({ SynApproval: "A1" }), "out_of_contract");
  assert.equal(anomaly({ SynAmount: numberToken("1.00") }), "out_of_contract"); // a readable amount reports a transaction
  assert.equal(anomaly({ SynReturn: 0, SynTip: "x" }), "out_of_contract", "an unreadable tip reports a transaction");
  // Final verification F1-2: an unreadable amount alone reports a transaction - a JSON string or an over-precise or
  // exponent token (DECISION D-064); the number 0 is readable under D-064 and reports one as well.
  for (const amount of ["12.3", "x", 0, numberToken("12.345"), numberToken("1e2")]) {
    assert.equal(anomaly({ SynError: false, SynReturn: 0, SynAmount: amount }), "out_of_contract", JSON.stringify(amount));
  }
  assert.equal(anomaly({ SynReturn: "0" }), "out_of_contract", "an unreadable return code: the result field is unreadable");
  // Verification V1-2: an error reply with an unreadable flag or currency alone reports no transaction.
  for (const extra of [{ SynCurrency: 0 }, { SynCurrency: "ils" }, { SynError: "yes" }, { SynPhone: "no" }]) {
    assert.deepEqual(lookup({ SynError: true, SynReturn: -77, ...extra }), { outcome: "failed", fields: {} }, JSON.stringify(extra));
  }
  assert.equal(anomaly({ SynReturn: 0, SynReference: "SYN-REF-1" }), "failed", "a readable reference never decides");
  assert.equal(anomaly({ SynReturn: 0, SynVoucher: "V 1" }), "failed", "a failing reference never decides");
  assert.deepEqual(lookup({ SynReturn: 12 }), { outcome: "failed", fields: {} });
  assert.deepEqual(lookup({}), { outcome: "failed", fields: {} });
  assert.deepEqual(lookup({ SynError: true }), { outcome: "failed", fields: {} });
});

test("release classification: confirmed only by error flag false AND a success return code", () => {
  assert.equal(release({ SynError: false, SynReturn: 0 }).outcome, "released");
  for (const reply of [{ SynError: true, SynReturn: 0 }, { SynError: false, SynReturn: -5 }, { SynReturn: 0 }, { SynError: false },
    {}, { SynError: "false", SynReturn: 0 }, { SynError: false, SynReturn: "0" }]) {
    assert.deepEqual(release(reply), { outcome: "release_failed", fields: {} }, JSON.stringify(reply));
  }
});

test("a truncated card number in a structured field is dropped before any RPC argument (reviews B1, LA-3)", () => {
  // Synthetic shapes built from zeros at run time: the SQL rule passes every one of them (its mask set has no
  // '-' or '_'); the engine drops them. A drop is masked_pattern, or the field's own charset / length rule.
  const z = (count) => "0".repeat(count);
  const shapes = [`${z(6)}---${z(4)}`, `${z(6)}${"_".repeat(6)}${z(4)}`, `${z(6)}-_-${z(4)}`, `${z(6)}--${z(4)}`, `${z(6)}__${z(4)}`,
    `${z(4)}-${z(2)}${"-".repeat(6)}${z(4)}`, `${z(4)}-${z(2)}${"-".repeat(8)}${z(4)}`, `${z(4)}_${z(2)}${"_".repeat(6)}${z(4)}`,
    `${z(4)}_${z(2)}${"_".repeat(5)}${z(4)}`, `${z(4)}-${z(2)}${"-".repeat(5)}${z(4)}`,
    `${z(6)}---${z(2)}-${z(2)}`, `${z(7)}--${z(4)}`, `${z(4)}-${z(3)}--${z(4)}`];
  for (const [name, field] of [["SynReference", "provider_reference"], ["SynDeposit", "deposit_id"], ["SynBrand", "card_brand_code"],
    ["SynEntry", "pan_entry_mode"], ["SynMethod", "payment_method_code"]]) {
    for (const [index, shape] of shapes.entries()) {
      const read = reading(providerReply({ [name]: shape }));
      assert.ok(!(field in read.values), `${field} shape ${index}`);
      assert.equal(read.failures.length, 1, `${field} shape ${index}`);
      assert.equal(read.failures[0].field, field);
      assert.ok(["masked_pattern", "charset", "length", "digit_run"].includes(read.failures[0].rule), `${field} shape ${index}`);
      if (safeTextFailure(shape, field) === null) assert.equal(read.failures[0].rule, "masked_pattern", `${field} shape ${index}`);
      const out = classifyCommit(profile, read);
      assert.equal(out.outcome, "approved", "a dropped non-essential field never blocks the outcome");
      assert.ok(!(field in out.fields));
    }
  }
  // In an essential code field the same shape is dropped and fails the outcome closed (verification V2-3).
  for (const shape of [`${z(4)}-${z(2)}${"-".repeat(5)}${z(4)}`, `${z(4)}_${z(2)}${"_".repeat(5)}${z(4)}`]) {
    const read = reading({ SynError: false, SynReturn: 0, SynApproval: shape });
    assert.deepEqual(read.failures, [{ field: "approval_type", rule: "masked_pattern" }]);
    const out = classifyCommit(profile, read);
    assert.equal(out.outcome, "unknown");
    assert.ok(!("approval_type" in out.fields));
    const status = reading({ SynStatus: shape });
    assert.deepEqual(status.failures, [{ field: "provider_status_code", rule: "masked_pattern" }]);
  }
  // Legitimate values pass: single separators, short groups, letters.
  for (const value of ["SYN-2026-1234", "INV-0000-0000", "A-B-C", `${z(4)}-${z(4)}`, `${z(3)}--${z(4)}`, "REF--1"]) {
    assert.equal(reading(providerReply({ SynReference: value })).values.provider_reference, value, value);
  }
  for (const value of ["CHIP", "EMV_CHIP", "A1", "S1", "CTLS-01", "AB_CD___EF"]) {
    assert.equal(reading(providerReply({ SynEntry: value })).values.pan_entry_mode, value, value);
  }
});

test("provider_saved_at follows PostgreSQL's timestamptz offset bound (at most 15:59)", () => {
  for (const offset of ["Z", "z", "+00:00", "+15:59", "-15:59", "+1559", "+15", "+14:00", "-0530", "+05"]) {
    const read = reading(providerReply({ SynSavedAt: `2026-10-27T10:00:05${offset}` }));
    assert.equal(read.values.provider_saved_at, `2026-10-27T10:00:05${offset}`, offset);
  }
  for (const offset of ["+16:00", "-16:00", "+1600", "+16", "+15:60", "+99:00", "+05:", ""]) {
    const read = reading(providerReply({ SynSavedAt: `2026-10-27T10:00:05${offset}` }));
    assert.ok(!("provider_saved_at" in read.values), offset);
    assert.deepEqual(read.failures, [{ field: "provider_saved_at", rule: "format" }], offset);
  }
});

test("nothing is logged: no console output on success, refusal, provider failure or an exception", async () => {
  const original = {};
  const writes = [];
  for (const method of ["log", "info", "warn", "error", "debug", "trace"]) {
    original[method] = console[method];
    console[method] = (...args) => writes.push([method, args.length]);
  }
  try {
    const ok = world({ rpc: { card_attempt_context: contextOk(), card_attempt_claim: freshClaim(),
      card_attempt_finish: envelope("approved") }, provider: { commit: providerReply() } });
    await ok.run(startTest());
    await ok.settle();
    const broken = world({ rpc: { card_attempt_context: contextOk({ attempt: contextAttempt("unknown") }),
      card_attempt_adapter_read: adapterRead("unknown"), card_attempt_finish: () => { throw new Error("boom"); } },
    provider: { lookup: () => { throw new Error("provider exploded with SYNTHETIC SECRET"); } } });
    await broken.run(statusInput());
    const thrower = world({ rpc: { card_attempt_context: () => { throw new Error("rpc exploded"); } } });
    await thrower.run(statusInput());
  } finally {
    for (const method of Object.keys(original)) console[method] = original[method];
  }
  assert.deepEqual(writes, []);
});
