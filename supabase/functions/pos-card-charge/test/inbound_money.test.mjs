// DECISION D-064 (BIZBOT-PAYMENTS-ZCREDIT-PILOT-001E-INBOUND-MONEY-NORMALIZATION-001): inbound provider money - the
// reply amount and tip - is read only as a raw JSON number token with zero, one or two fraction digits and reaches
// card_attempt_finish only as its canonical two-decimal lexeme; the outbound amount, SQL and every other reply field
// are unchanged. Every expectation is a literal, never derived from the engine's own reader or classifier. Scripted
// RPC tests (a fake provider and a fake PostgREST), not PostgreSQL integration tests: SQL is unchanged, and its finish
// rule is read here from the migration text.
import "./no_network.mjs";
import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { adapterRead, blocked, contextAttempt, contextOk, DUPLICATE_KEY, envelope, freshClaim, LIVE_ENV, QUERY_KEY, releaseInput,
  settleAll, startLive, startTest, statusInput, stray, SYNTHETIC_PROFILE, world } from "./fixtures.mjs";
import { AMOUNT_LEXEME, canonicalInboundMoney, INBOUND_MONEY_TOKEN, MAX_MINOR, minorFromLexeme } from "../lib/money.mjs";
import { JsonError, JsonNumber, parseJson } from "../lib/json.mjs";
import { ProfileError, validateProfile } from "../lib/provider/engine.mjs";

test.after(async () => { await settleAll(); assert.deepEqual(blocked, []); assert.deepEqual(stray, []); });

const FUNCTION_DIR = new URL("../", import.meta.url);
const REPO = new URL("../../../../", import.meta.url);
const read = async (url) => (await readFile(url, "utf8")).replace(/\r\n/g, "\n");

// [raw number token, its canonical lexeme, the minor units SQL derives from that lexeme] (API_CONTRACT section 4.55.5).
const ACCEPTED = [
  ["0", "0.00", 0n], ["0.0", "0.00", 0n], ["0.00", "0.00", 0n], ["0.5", "0.50", 50n], ["0.05", "0.05", 5n], ["0.01", "0.01", 1n],
  ["1", "1.00", 100n], ["12", "12.00", 1200n], ["12.0", "12.00", 1200n], ["12.00", "12.00", 1200n], ["12.3", "12.30", 1230n],
  ["12.30", "12.30", 1230n], ["12.34", "12.34", 1234n], ["10.35", "10.35", 1035n], ["100", "100.00", 10000n],
  ["100000000", "100000000.00", 10000000000n], ["999999999", "999999999.00", 99999999900n],
  ["999999999.9", "999999999.90", 99999999990n], ["999999999.99", "999999999.99", 99999999999n],
];
// JSON number tokens the strict parser keeps but D-064 refuses: a third fraction digit (even a zero), an exponent, a
// sign (-0 included) and a tenth integer digit.
const REFUSED_TOKENS = ["12.345", "12.300", "0.000", "999999999.999", "1e2", "1E2", "1e+2", "1e-2", "0e0", "12.3e0", "-12", "-0",
  "-0.0", "-0.00", "-12.30", "1000000000", "1000000000.00", "1000000000.5", "9999999999.99", "123456789012"];
// Texts that are no JSON value at all: the JsonNumber constructor and the strict parser refuse them before any field.
const NOT_TOKENS = ["01", "00", "00.00", "012.34", "12.", ".30", "+12", "+0", "1,234.00", "12,30", "0x10", "NaN", "Infinity", "",
  String.fromCodePoint(0x0661, 0x0662), String.fromCodePoint(0xff11, 0xff12)];

test("D-064 direct: every accepted token is right-padded to its canonical two-decimal lexeme", () => {
  assert.equal(String(INBOUND_MONEY_TOKEN), String(/^(0|[1-9][0-9]{0,8})(?:\.([0-9]{1,2}))?$/));
  for (const [text, lexeme, minor] of ACCEPTED) {
    assert.ok(INBOUND_MONEY_TOKEN.test(text), text);
    assert.equal(canonicalInboundMoney(new JsonNumber(text)), lexeme, text);
    assert.equal(minorFromLexeme(lexeme), minor, `${text}: the BigInt conversion of the canonical text`);
  }
  assert.equal(minorFromLexeme(canonicalInboundMoney(new JsonNumber("999999999.99"))), MAX_MINOR, "the bound is MAX_MINOR");
});

test("D-064 direct: a sign, an exponent, a third fraction digit, a tenth integer digit, a string or any other value is refused", () => {
  for (const text of REFUSED_TOKENS) {
    assert.ok(!INBOUND_MONEY_TOKEN.test(text), text);
    assert.equal(canonicalInboundMoney(new JsonNumber(text)), null, text);
  }
  for (const text of NOT_TOKENS) {
    const label = JSON.stringify(text);
    assert.throws(() => new JsonNumber(text), TypeError, `${label}: never a JsonNumber`);
    assert.throws(() => parseJson(`{"SynAmount":${text}}`), JsonError, `${label}: the strict parser refuses the whole reply`);
    assert.ok(!INBOUND_MONEY_TOKEN.test(text), `${label}: the grammar refuses the text as well`);
    assert.equal(canonicalInboundMoney(text), null, `${label}: a string is never read`);
  }
  // A JsonNumber is required: a string (a well-formed lexeme included), a JavaScript number, a BigInt or any other value is refused.
  const others = [["12", "a string"], ["12.30", "a lexeme string"], ["0.00", "a zero string"], ["0", "a zero string"],
    [12, "a JavaScript number"], [12.3, "a JavaScript number"], [0, "a JavaScript zero"], [12n, "a BigInt"], [null, "null"],
    [undefined, "undefined"], [true, "true"], [false, "false"], [[new JsonNumber("12")], "an array"], [{ text: "12" }, "a plain object"]];
  for (const [value, label] of others) assert.equal(canonicalInboundMoney(value), null, label);
});

test("D-064 parity: every canonical output is a JSON string that passes the finish rule read from the migration", async () => {
  const migration = await read(new URL("supabase/migrations/20261109143313_bizbot_zcredit_001e_drop_evidence_001.sql", REPO));
  const rule = /when 'provider_amount', 'tip_amount' then\n\s+if v_text is null or v_text !~ '([^']+)' then v_rule := 'format'; end if;/
    .exec(migration);
  assert.ok(rule, "the finish rule of the amount and the tip");
  assert.equal(rule[1], AMOUNT_LEXEME.source, "the finish rule is the canonical lexeme");
  assert.match(migration, /v_amount := split_part\(v_text, '\.', 1\)::bigint \* 100 \+ split_part\(v_text, '\.', 2\)::bigint;/);
  assert.match(migration, /v_tip := split_part\(v_text, '\.', 1\)::bigint \* 100 \+ split_part\(v_text, '\.', 2\)::bigint;/);
  const finishRule = new RegExp(rule[1]);
  for (const [text, lexeme, minor] of ACCEPTED) {
    const out = canonicalInboundMoney(new JsonNumber(text));
    assert.equal(out, lexeme, text);
    assert.equal(typeof out, "string", `${text}: a JSON string (the finish refuses a JSON number, FR-124)`);
    assert.ok(finishRule.test(out), `${text}: ${out} passes the finish rule`);
    const [major, fraction] = out.split("."); // split_part(v_text, '.', 1) * 100 + split_part(v_text, '.', 2)
    assert.equal(BigInt(major) * 100n + BigInt(fraction), minor, `${text}: the finish's integer conversion`);
  }
});

test("D-064 schema: a wire profile cannot accept a JSON string for either amount key", () => {
  const clone = (value) => JSON.parse(JSON.stringify(value));
  for (const [key, accept] of [["provider_amount", ["string"]], ["provider_amount", ["string", "number"]],
    ["provider_amount", ["number", "string"]], ["tip_amount", ["string"]], ["tip_amount", ["number", "string"]]]) {
    const copy = clone(SYNTHETIC_PROFILE);
    copy.reply[key].accept = accept;
    assert.throws(() => validateProfile(copy), ProfileError, `${key} ${JSON.stringify(accept)}`);
  }
  const profile = validateProfile(SYNTHETIC_PROFILE);
  assert.deepEqual([...profile.reply.provider_amount.accept], ["number"]);
  assert.deepEqual([...profile.reply.tip_amount.accept], ["number"]);
});

const finishOf = (w) => w.calls.rpc.filter((call) => call.name === "card_attempt_finish");
const finishEcho = (body) => envelope({ approved: "approved", declined: "declined" }[body.p_outcome] ?? "unknown",
  { mode: body.p_mode, ...(body.p_outcome === "approved" && body.p_mode === "live" ? { recoverable: false, resume_count: 0 } : {}) });
const rawReply = (text) => () => new Response(text, { status: 200, headers: { "content-type": "application/json" } });

async function commitOnce(mode, text) {
  const w = world({ ...(mode === "live" ? { env: LIVE_ENV } : {}), rpc: { card_attempt_context: contextOk(),
    card_attempt_claim: freshClaim(mode), card_attempt_finish: finishEcho }, provider: { commit: rawReply(text) } });
  const out = await w.run(mode === "live" ? startLive() : startTest());
  await w.settle();
  assert.deepEqual(w.calls.provider.map((call) => call.op), ["commit"], `${text}: one commit, no lookup, no retry`);
  const finishes = finishOf(w);
  assert.equal(finishes.length, 1, text);
  return { w, out, finish: finishes[0] };
}

/** One status call on an 'unknown' attempt of `amountMinor`; the scripted finish echoes the outcome (not the SQL rule). */
async function lookupOnce(mode, text, amountMinor = 1234) {
  const w = world({ ...(mode === "live" ? { env: LIVE_ENV } : {}), rpc: {
    card_attempt_context: contextOk({ attempt: contextAttempt("unknown", mode, { amount_minor: amountMinor }) }),
    card_attempt_adapter_read: adapterRead("unknown", mode, { amount_minor: amountMinor }), card_attempt_finish: finishEcho },
  provider: { lookup: rawReply(text) } });
  const out = await w.run(statusInput());
  assert.deepEqual(w.calls.provider.map((call) => call.op), ["lookup"], `${text}: one lookup, no commit`);
  const finishes = finishOf(w);
  assert.equal(finishes.length, 1, text);
  return { w, out, finish: finishes[0] };
}

/** No refused token enters any RPC argument or the POS answer. */
function assertNeverForwarded(w, out, token, field, label) {
  const everything = `${w.calls.rpc.map((call) => call.raw).join("\n")}\n${out.text}`;
  assert.ok(!everything.includes(`"${field}":`), `${label}: no ${field} value is forwarded`);
  if (token.length >= 4 && /[0-9]/.test(token)) assert.ok(!everything.includes(token), `${label}: ${token} never enters an RPC argument or the answer`);
}

const APPROVE = '"SynError":false,"SynReturn":0,"SynApproval":"A1","SynPhone":false';
const approveFields = { error_flag: false, provider_return_code: 0, approval_type: "A1", phone_authorization: false };
const DECLINE = '"SynError":true,"SynReturn":3,"SynApproval":"D1","SynPhone":false';
const declineFields = { error_flag: true, provider_return_code: 3, approval_type: "D1", phone_authorization: false };
const tipDropped = { dropped_fields: [{ field: "tip_amount", rule: "format" }] };
const OOC = { anomaly_code: "out_of_contract", provider_return_class: "unclassified" };

test("D-064 commit: a tip absent, null, 0, 0.0 or 0.00 approves; the finish gets no tip or 0.00 (LIVE and TEST)", async () => {
  const cases = [
    [`{${APPROVE}}`, { ...approveFields, provider_return_class: "approved" }],
    [`{${APPROVE},"SynTip":null}`, { ...approveFields, provider_return_class: "approved" }],
    [`{${APPROVE},"SynTip":0}`, { ...approveFields, tip_amount: "0.00", provider_return_class: "approved" }],
    [`{${APPROVE},"SynTip":0.0}`, { ...approveFields, tip_amount: "0.00", provider_return_class: "approved" }],
    [`{${APPROVE},"SynTip":0.00}`, { ...approveFields, tip_amount: "0.00", provider_return_class: "approved" }],
  ];
  for (const mode of ["live", "test"]) {
    for (const [text, fields] of cases) {
      const { finish } = await commitOnce(mode, text);
      assert.equal(finish.body.p_source, "commit", `${mode} ${text}`);
      assert.equal(finish.body.p_outcome, "approved", `${mode} ${text}`);
      assert.deepEqual(finish.body.p_provider_fields, fields, `${mode} ${text}`);
    }
  }
});

test("D-064 commit: a readable non-zero tip is amount_mismatch, an unreadable one out_of_contract, a decline keeps its outcome", async () => {
  const mismatch = (tip) => ({ ...approveFields, tip_amount: tip, anomaly_code: "amount_mismatch", provider_return_class: "approved" });
  const cases = [
    // [reply, outcome, exact finish fields, the refused token that must never be forwarded]
    [`{${APPROVE},"SynTip":5}`, "anomaly", mismatch("5.00")],
    [`{${APPROVE},"SynTip":5.0}`, "anomaly", mismatch("5.00")],
    [`{${APPROVE},"SynTip":5.00}`, "anomaly", mismatch("5.00")],
    [`{${APPROVE},"SynTip":0.01}`, "anomaly", mismatch("0.01")],
    [`{${APPROVE},"SynTip":0.1}`, "anomaly", mismatch("0.10")],
    [`{${APPROVE},"SynTip":999999999.99}`, "anomaly", mismatch("999999999.99")],
    [`{${APPROVE},"SynTip":"0"}`, "anomaly", { ...approveFields, ...OOC, ...tipDropped }, '"0"'],
    [`{${APPROVE},"SynTip":"0.00"}`, "anomaly", { ...approveFields, ...OOC, ...tipDropped }, '"0.00"'],
    [`{${APPROVE},"SynTip":0.000}`, "anomaly", { ...approveFields, ...OOC, ...tipDropped }, "0.000"],
    [`{${APPROVE},"SynTip":7.125}`, "anomaly", { ...approveFields, ...OOC, ...tipDropped }, "7.125"],
    [`{${APPROVE},"SynTip":1e0}`, "anomaly", { ...approveFields, ...OOC, ...tipDropped }, "1e0"],
    [`{${APPROVE},"SynTip":-0}`, "anomaly", { ...approveFields, ...OOC, ...tipDropped }, "-0"],
    [`{${APPROVE},"SynTip":-5}`, "anomaly", { ...approveFields, ...OOC, ...tipDropped }, "-5"],
    [`{${APPROVE},"SynTip":1000000000}`, "anomaly", { ...approveFields, ...OOC, ...tipDropped }, "1000000000"],
    [`{${APPROVE},"SynTip":true}`, "anomaly", { ...approveFields, ...OOC, ...tipDropped }],
    [`{${APPROVE},"SynTip":{}}`, "anomaly", { ...approveFields, ...OOC, ...tipDropped }],
    [`{${APPROVE},"SynTip":[]}`, "anomaly", { ...approveFields, ...OOC, ...tipDropped }],
    // The declined precedence: a declined type declines whatever readable tip it carries; an unreadable tip still decides first.
    [`{${DECLINE},"SynTip":0}`, "declined", { ...declineFields, tip_amount: "0.00", provider_return_class: "declined" }],
    [`{${DECLINE},"SynTip":5}`, "declined", { ...declineFields, tip_amount: "5.00", provider_return_class: "declined" }],
    [`{${DECLINE},"SynTip":5.00}`, "declined", { ...declineFields, tip_amount: "5.00", provider_return_class: "declined" }],
    [`{${DECLINE},"SynTip":0.000}`, "anomaly", { ...declineFields, ...OOC, ...tipDropped }, "0.000"],
    [`{${DECLINE},"SynTip":"0.00"}`, "anomaly", { ...declineFields, ...OOC, ...tipDropped }, '"0.00"'],
  ];
  for (const mode of ["live", "test"]) {
    for (const [text, outcome, fields, token] of cases) {
      const label = `${mode} ${text}`;
      const { w, out, finish } = await commitOnce(mode, text);
      assert.equal(finish.body.p_outcome, outcome, label);
      assert.deepEqual(finish.body.p_provider_fields, fields, label);
      if (token !== undefined) assertNeverForwarded(w, out, token, "tip_amount", label);
    }
  }
});

test("D-064 commit: a readable tip leaves a reply that is not otherwise approvable UNKNOWN (phone, duplicate, error, code, type)", async () => {
  // D-064 point 4 applies the tip rule to an otherwise approvable reply only: the commit order is unchanged (review TE-1).
  const bases = [
    ['"SynError":false,"SynReturn":0,"SynApproval":"A1","SynPhone":true',
      { error_flag: false, provider_return_code: 0, approval_type: "A1", phone_authorization: true }, "phone_authorization"],
    ['"SynError":false,"SynReturn":-901,"SynApproval":"A1","SynPhone":false',
      { error_flag: false, provider_return_code: -901, approval_type: "A1", phone_authorization: false }, "duplicate"],
    ['"SynError":true,"SynReturn":0,"SynApproval":"A1","SynPhone":false',
      { error_flag: true, provider_return_code: 0, approval_type: "A1", phone_authorization: false }, "error"],
    ['"SynError":false,"SynReturn":5,"SynApproval":"A1","SynPhone":false',
      { error_flag: false, provider_return_code: 5, approval_type: "A1", phone_authorization: false }, "unclassified"],
    ['"SynError":false,"SynReturn":0,"SynApproval":"ZZ","SynPhone":false',
      { error_flag: false, provider_return_code: 0, approval_type: "ZZ", phone_authorization: false }, "unclassified"],
    ['"SynError":false,"SynReturn":0,"SynPhone":false',
      { error_flag: false, provider_return_code: 0, phone_authorization: false }, "unclassified"],
  ];
  for (const mode of ["live", "test"]) {
    for (const [base, fields, returnClass] of bases) {
      for (const [tip, lexeme] of [["5", "5.00"], ["5.00", "5.00"], ["0.01", "0.01"], ["0", "0.00"]]) {
        const text = `{${base},"SynTip":${tip}}`;
        const { finish } = await commitOnce(mode, text);
        assert.equal(finish.body.p_outcome, "unknown", `${mode} ${text}`);
        assert.deepEqual(finish.body.p_provider_fields, { ...fields, tip_amount: lexeme, provider_return_class: returnClass },
          `${mode} ${text}`);
      }
    }
  }
});

test("D-064 commit: an echoed amount is read the same way (a string is refused)", async () => {
  const { finish } = await commitOnce("live", `{${APPROVE},"SynAmount":12.34}`);
  assert.equal(finish.body.p_outcome, "approved");
  assert.deepEqual(finish.body.p_provider_fields, { ...approveFields, provider_amount: "12.34", provider_return_class: "approved" });
  const whole = await commitOnce("live", `{${APPROVE},"SynAmount":12}`);
  assert.equal(whole.finish.body.p_outcome, "approved");
  assert.equal(whole.finish.body.p_provider_fields.provider_amount, "12.00");
  const string = await commitOnce("live", `{${APPROVE},"SynAmount":"12.34"}`);
  assert.equal(string.finish.body.p_outcome, "unknown", "a failing essential field: UNKNOWN (001D M2)");
  assert.deepEqual(string.finish.body.p_provider_fields, { ...approveFields, provider_return_class: "unclassified",
    dropped_fields: [{ field: "provider_amount", rule: "format" }] });
});

const FOUND = '"SynError":false,"SynReturn":0,"SynStatus":"S1","SynCurrency":1';
const foundFields = { error_flag: false, provider_return_code: 0, provider_status_code: "S1", provider_currency: "ILS" };

test("D-064 lookup: 12, 12.0, 12.00 and 12.3, 12.30 reach the finish as 12.00 and 12.30 beside the attempt's exact amount", async () => {
  // [attempt amount_minor, the TransactionSum token, the lexeme the finish receives]: SQL converts the lexeme and compares it
  // with p_amount_minor by strict integer equality (FR-102: equal -> approved; FR-104: different -> amount_mismatch).
  const cases = [[1200, "12", "12.00"], [1200, "12.0", "12.00"], [1200, "12.00", "12.00"], [1230, "12.3", "12.30"],
    [1230, "12.30", "12.30"], [1234, "12.34", "12.34"], [1035, "10.35", "10.35"], [99999999999, "999999999.99", "999999999.99"],
    [99999999990, "999999999.9", "999999999.90"],
    // Different amounts reach the finish as canonical text too, for SQL's amount_mismatch: a zero is readable.
    [1234, "12.3", "12.30"], [1234, "12", "12.00"], [1200, "12.01", "12.01"], [1234, "0", "0.00"], [1234, "0.00", "0.00"]];
  for (const mode of ["live", "test"]) {
    for (const [amountMinor, token, lexeme] of cases) {
      const label = `${mode} ${amountMinor} ${token}`;
      const { finish } = await lookupOnce(mode, `{${FOUND},"SynAmount":${token}}`, amountMinor);
      assert.equal(finish.body.p_source, "lookup", label);
      assert.equal(finish.body.p_outcome, "approved", label);
      assert.equal(finish.body.p_amount_minor, amountMinor, label);
      assert.deepEqual(finish.body.p_provider_fields, { ...foundFields, provider_amount: lexeme, provider_return_class: "approved" },
        label);
    }
  }
  // A zero tip on a found lookup is read the same way (SQL's lookup tip check sees 0.00).
  const tip = await lookupOnce("live", `{${FOUND},"SynAmount":12,"SynTip":0}`, 1200);
  assert.deepEqual(tip.finish.body.p_provider_fields, { ...foundFields, provider_amount: "12.00", tip_amount: "0.00",
    provider_return_class: "approved" });
});

test("D-064 lookup: a readable non-zero tip on a found lookup reaches the finish as its canonical lexeme (SQL: amount_mismatch, FR-107)", async () => {
  // SQL's lookup approval requires a zero tip (coalesce(v_tip, 0) = 0), so the tip must reach the finish whatever its value
  // (D-064 point 4; reviews F1 and TE-2).
  for (const mode of ["live", "test"]) {
    for (const [tip, lexeme] of [["5", "5.00"], ["5.0", "5.00"], ["5.00", "5.00"], ["0.01", "0.01"], ["0.1", "0.10"]]) {
      const text = `{${FOUND},"SynAmount":12,"SynTip":${tip}}`;
      const { finish } = await lookupOnce(mode, text, 1200);
      assert.equal(finish.body.p_outcome, "approved", `${mode} ${text}`);
      assert.deepEqual(finish.body.p_provider_fields, { ...foundFields, provider_amount: "12.00", tip_amount: lexeme,
        provider_return_class: "approved" }, `${mode} ${text}`);
    }
  }
});

test("D-064 lookup: a malformed or over-precise amount is out_of_contract with only its format token; nothing else moves", async () => {
  const anomaly = { ...foundFields, ...OOC, dropped_fields: [{ field: "provider_amount", rule: "format" }] };
  for (const mode of ["live", "test"]) {
    for (const token of ["12.345", "12.300", "1e2", "-12", "-0", "1000000000", '"12.34"', '"12"', "true"]) {
      const label = `${mode} ${token}`;
      const { w, out, finish } = await lookupOnce(mode, `{${FOUND},"SynAmount":${token}}`);
      assert.equal(finish.body.p_outcome, "anomaly", label);
      assert.deepEqual(finish.body.p_provider_fields, anomaly, label);
      assertNeverForwarded(w, out, token, "provider_amount", label);
    }
  }
});

test("D-064 lookup: the D-063 precedence and the not-found / pending paths are unchanged by a readable amount", async () => {
  const cases = [
    // [reply, outcome, exact finish fields]
    ['{"SynError":false,"SynReturn":0,"SynStatus":"S7","SynAmount":12,"SynCurrency":1}', "anomaly",
      { error_flag: false, provider_return_code: 0, provider_status_code: "S7", provider_amount: "12.00", provider_currency: "ILS", ...OOC }],
    ['{"SynStatus":"S7","SynApproval":"D1","SynAmount":12.3}', "anomaly",
      { provider_status_code: "S7", approval_type: "D1", provider_amount: "12.30", ...OOC }],
    ['{"SynError":true,"SynReturn":-404,"SynAmount":12.3}', "not_found",
      { error_flag: true, provider_return_code: -404, provider_amount: "12.30", provider_return_class: "not_found" }],
    ['{"SynError":true,"SynReturn":-404,"SynAmount":12.345}', "not_found",
      { error_flag: true, provider_return_code: -404, provider_return_class: "not_found",
        dropped_fields: [{ field: "provider_amount", rule: "format" }] }],
    ['{"SynError":false,"SynReturn":-102,"SynAmount":12}', "pending",
      { error_flag: false, provider_return_code: -102, provider_amount: "12.00", provider_return_class: "pending" }],
    ['{"SynStatus":"S3","SynAmount":12}', "anomaly",
      { provider_status_code: "S3", provider_amount: "12.00", anomaly_code: "voided", provider_return_class: "unclassified" }],
    ['{"SynError":false,"SynReturn":0,"SynAmount":12}', "anomaly",
      { error_flag: false, provider_return_code: 0, provider_amount: "12.00", ...OOC }], // a readable amount reports a transaction
    ['{"SynError":true,"SynReturn":-7,"SynApproval":"D2","SynAmount":12.3}', "declined",
      { error_flag: true, provider_return_code: -7, approval_type: "D2", provider_amount: "12.30", provider_return_class: "declined" }],
    ['{"SynError":true,"SynReturn":-7,"SynApproval":"D2","SynAmount":12.345}', "anomaly",
      { error_flag: true, provider_return_code: -7, approval_type: "D2", ...OOC,
        dropped_fields: [{ field: "provider_amount", rule: "format" }] }],
    // A readable tip or amount follows the D-063 rules exactly as a two-decimal one did at the W1 head (review F2): beside
    // a declined type with no status it declines; a tip alone reports no provider fact; beside a listed anomaly status it
    // yields that status's code (beside an approved status it reaches SQL's tip check, the test above).
    ['{"SynError":true,"SynReturn":-7,"SynApproval":"D2","SynTip":5}', "declined",
      { error_flag: true, provider_return_code: -7, approval_type: "D2", tip_amount: "5.00", provider_return_class: "declined" }],
    ['{"SynError":false,"SynReturn":0,"SynTip":5}', "failed", {}],
    ['{"SynStatus":"S3","SynTip":5}', "anomaly",
      { provider_status_code: "S3", tip_amount: "5.00", anomaly_code: "voided", provider_return_class: "unclassified" }],
    ['{"SynStatus":"S4","SynAmount":12}', "anomaly",
      { provider_status_code: "S4", provider_amount: "12.00", anomaly_code: "refunded", provider_return_class: "unclassified" }],
  ];
  for (const mode of ["live", "test"]) {
    for (const [text, outcome, fields] of cases) {
      const { finish } = await lookupOnce(mode, text);
      assert.equal(finish.body.p_outcome, outcome, `${mode} ${text}`);
      assert.deepEqual(finish.body.p_provider_fields, fields, `${mode} ${text}`);
    }
  }
});

test("D-064 release: the shared reply reader reports a refused money value as its format token and never forwards one", async () => {
  // A release finish carries only the D-062 evidence, never a provider value (review DOC-2).
  const releaseOnce = async (mode, text) => {
    const w = world({ ...(mode === "live" ? { env: LIVE_ENV } : {}), rpc: {
      card_attempt_context: contextOk({ attempt: contextAttempt("sent", mode) }), card_attempt_adapter_read: adapterRead("sent", mode),
      card_attempt_mark_release_requested: envelope("sent", { mode }),
      card_attempt_finish: (body) => envelope(body.p_outcome === "released" ? "released" : "sent", { mode: body.p_mode }) },
    provider: { release: rawReply(text) } });
    await w.run(releaseInput());
    assert.deepEqual(w.calls.provider.map((call) => call.op), ["release"], `${text}: one release, no commit, no lookup`);
    const finishes = finishOf(w);
    assert.equal(finishes.length, 1, text);
    return finishes[0];
  };
  const cases = [
    ['{"SynError":false,"SynReturn":0,"SynAmount":12,"SynTip":0}', {}],
    ['{"SynError":false,"SynReturn":0,"SynAmount":12.3,"SynTip":5}', {}],
    ['{"SynError":false,"SynReturn":0,"SynAmount":"12.34"}', { dropped_fields: [{ field: "provider_amount", rule: "format" }] }],
    ['{"SynError":false,"SynReturn":0,"SynTip":0.000}', { dropped_fields: [{ field: "tip_amount", rule: "format" }] }],
  ];
  for (const mode of ["live", "test"]) {
    for (const [text, fields] of cases) {
      const finish = await releaseOnce(mode, text);
      assert.equal(finish.body.p_source, "release", `${mode} ${text}`);
      assert.equal(finish.body.p_outcome, "released", `${mode} ${text}`);
      assert.deepEqual(finish.body.p_provider_fields, fields, `${mode} ${text}`);
    }
  }
});

test("D-064 outbound: the commit request bytes are unchanged for existing amounts (whole body, literal)", async () => {
  const body = (terminal, password, pad, token) => `{"syn_terminal":"${terminal}","syn_password":"${password}","syn_pad":"PAD${pad}",`
    + `"syn_amount":${token},"syn_currency":1,"syn_kind":"regular","syn_installments":1,"syn_present":true,`
    + `"syn_status_key":"${QUERY_KEY}","syn_duplicate_key":"${DUPLICATE_KEY}"}`;
  for (const [amount, mode, token] of [[1, "test", "0.01"], [100, "test", "1.00"], [1234, "test", "12.34"], [5000, "test", "50.00"],
    [2500000, "live", "25000.00"], [99999999999, "live", "999999999.99"]]) {
    const w = world({ ...(mode === "live" ? { env: LIVE_ENV } : {}), rpc: { card_attempt_context: contextOk(),
      card_attempt_claim: { ...freshClaim(mode), amount_minor: amount },
      card_attempt_finish: () => ({ ...envelope("approved", { mode }), amount_minor: amount }) },
    provider: { commit: rawReply(`{${APPROVE}}`) } });
    await w.run(mode === "test" ? startTest({ amount_minor: amount }) : startLive({ amount_minor: amount }));
    await w.settle();
    assert.equal(w.calls.provider.length, 1, token);
    const expected = mode === "test" ? body("SYNTERM", "SYNPASS-TEST", "SYNPAD1", token) : body("SYNLIVE", "SYNPASS-LIVE", "SYNPAD2", token);
    assert.equal(w.calls.provider[0].raw, expected, token);
  }
});

test("D-064 static: the outbound helpers keep their code; the reader's amount case calls the inbound canonicalizer", async () => {
  const code = (text) => text.split("\n").filter((line) => !/^\s*\/\//.test(line)).join("\n").replace(/\/\*[\s\S]*?\*\//g, "");
  const money = code(await read(new URL("lib/money.mjs", FUNCTION_DIR)));
  for (const body of [
    "export const MAX_MINOR = 99999999999n;",
    "export const AMOUNT_LEXEME = /^(0|[1-9][0-9]{0,8})\\.[0-9]{2}$/;",
    "export function minorFromToken(value) {\n  if (!(value instanceof JsonNumber) || !/^[1-9][0-9]{0,10}$/.test(value.text)) return null;\n"
      + "  const minor = BigInt(value.text);\n  return minor <= MAX_MINOR ? minor : null;\n}",
    "export function lexemeFromMinor(minor) {\n  if (typeof minor !== \"bigint\" || minor < 1n || minor > MAX_MINOR) throw new RangeError(\"amount outside the bound\");\n"
      + "  const major = minor / 100n;\n  const fraction = minor % 100n;\n"
      + "  const lexeme = `${major}.${fraction < 10n ? \"0\" : \"\"}${fraction}`;\n"
      + "  if (!AMOUNT_LEXEME.test(lexeme)) throw new RangeError(\"amount outside the grammar\");\n  return lexeme;\n}",
    "export function amountToken(minor) {\n  return new JsonNumber(lexemeFromMinor(minor));\n}",
    "export function minorFromLexeme(text) {\n  if (typeof text !== \"string\" || !AMOUNT_LEXEME.test(text)) return null;\n"
      + "  const [major, fraction] = text.split(\".\");\n  return BigInt(major) * 100n + BigInt(fraction);\n}",
    // The inbound helper is pinned too: a float round trip such as String(+text) would pass every behavioural test
    // inside the bound (review TE-3), so its text-only body is part of the guard.
    "export const INBOUND_MONEY_TOKEN = /^(0|[1-9][0-9]{0,8})(?:\\.([0-9]{1,2}))?$/;",
    "export function canonicalInboundMoney(value) {\n  if (!(value instanceof JsonNumber)) return null;\n"
      + "  const match = INBOUND_MONEY_TOKEN.exec(value.text);\n  if (match === null) return null;\n"
      + "  const lexeme = `${match[1]}.${(match[2] ?? \"\").padEnd(2, \"0\")}`;\n"
      + "  return AMOUNT_LEXEME.test(lexeme) ? lexeme : null;\n}",
  ]) assert.ok(money.includes(body), body.split("\n")[0]);
  assert.ok(!/JSON\.parse|globalThis|\beval\b/.test(money), "no parse, global or eval escape hatch in the money module");
  const engine = code(await read(new URL("lib/provider/engine.mjs", FUNCTION_DIR)));
  assert.match(engine, /case "amount": \{[^\n]*\n\s+const lexeme = accepts\("number"\) \? canonicalInboundMoney\(raw\) : null;\n\s+return lexeme !== null \? \{ value: lexeme \} : \{ rule: "format" \};\n\s+\}/);
  assert.match(engine, /\n {2}amount: \["number"\], currency: \["string", "number"\], timestamp: \["string"\] \}\);/);
  assert.ok(!/AMOUNT_LEXEME/.test(engine), "the reader no longer applies the canonical grammar to raw reply text");
  assert.equal([...engine.matchAll(/canonicalInboundMoney\(/g)].length, 1, "one call site: the amount case");
  assert.match(engine, /case "amount": body\[spec\.name\] = amountToken\(ctx\.amountMinor\); break;/, "the outbound amount is unchanged");
});
