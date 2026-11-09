// DECISION D-062 (BIZBOT-PAYMENTS-ZCREDIT-PILOT-001E-DROP-EVIDENCE-001): for a 2xx reply that is a readable JSON
// object, every allowlisted field the adapter drops reaches card_attempt_finish as exactly its {field, rule}
// tokens in p_provider_fields.dropped_fields - on the commit, lookup and release finish - and never as a value;
// the finish carries exactly the classified fields plus that evidence, and a reply with no failing field leaves
// the arguments as 001E built them. Scripted RPC tests (a fake provider and a fake PostgREST), not PostgreSQL
// integration tests: the SQL side is proven by the pgTAP lane
// supabase/tests/bizbot_zcredit_001e_drop_evidence_test.sql on a disposable local database.
import "./no_network.mjs";
import test from "node:test";
import assert from "node:assert/strict";
import { readdir, readFile } from "node:fs/promises";
import { adapterRead, blocked, contextAttempt, contextOk, envelope, freshClaim, LIVE_ENV, numberToken, providerReply,
  releaseInput, settleAll, startLive, startTest, statusInput, stray, SYNTHETIC_PROFILE, world } from "./fixtures.mjs";
import { classifyCommit, classifyLookup, classifyRelease, extractReply, REPLY_KEY_TABLE, validateProfile }
  from "../lib/provider/engine.mjs";
import { parseJson, stringifyJson } from "../lib/json.mjs";

test.after(async () => { await settleAll(); assert.deepEqual(blocked, []); assert.deepEqual(stray, []); });

const RULES = ["charset", "length", "control_character", "digit_run", "masked_pattern", "format"];
const profile = validateProfile(SYNTHETIC_PROFILE);
const finishOf = (w) => w.calls.rpc.filter((call) => call.name === "card_attempt_finish");
const read = (reply, mode) => extractReply(profile, parseJson(JSON.stringify(reply)), { mode });
const extracted = (reply, mode) => read(reply, mode).failures.map(({ field, rule }) => ({ field, rule }));
/**
 * What the finish must carry for one reply: exactly the classified fields, plus the evidence when a field failed,
 * serialized as the adapter serializes it (number tokens as JSON numbers).
 */
function expectedFields(reply, mode, operation) {
  const reading = read(reply, mode);
  const classify = { commit: classifyCommit, lookup: classifyLookup, release: classifyRelease }[operation];
  const { fields } = classify(profile, reading);
  const dropped = reading.failures.map(({ field, rule }) => ({ field, rule }));
  return JSON.parse(stringifyJson(dropped.length ? { ...fields, dropped_fields: dropped } : fields));
}
// Synthetic failing values, built at run time so that no card-shaped literal sits in the source.
const twelveDigits = "0".repeat(12);
const masked = `${"0".repeat(4)}x${"0".repeat(4)}`;
const truncated = `${"0".repeat(6)}${"-".repeat(6)}${"0".repeat(4)}`;
const zwsp = "​";

const finishEcho = (body) => {
  const state = { approved: "approved", declined: "declined", released: "released" }[body.p_outcome] ?? "unknown";
  return envelope(state, { mode: body.p_mode, ...(state === "approved" && body.p_mode === "live"
    ? { recoverable: false, resume_count: 0 } : {}) });
};
const startWorld = (mode, reply) => world({ ...(mode === "live" ? { env: LIVE_ENV } : {}),
  rpc: { card_attempt_context: contextOk(), card_attempt_claim: freshClaim(mode), card_attempt_finish: finishEcho },
  provider: { commit: reply } });
const statusWorld = (mode, reply) => world({ ...(mode === "live" ? { env: LIVE_ENV } : {}),
  rpc: { card_attempt_context: contextOk({ attempt: contextAttempt("unknown", mode) }),
    card_attempt_adapter_read: adapterRead("unknown", mode), card_attempt_finish: finishEcho },
  provider: { lookup: reply } });
const releaseWorld = (mode, reply) => world({ ...(mode === "live" ? { env: LIVE_ENV } : {}),
  rpc: { card_attempt_context: contextOk({ attempt: contextAttempt("sent", mode) }),
    card_attempt_adapter_read: adapterRead("sent", mode), card_attempt_mark_release_requested: envelope("sent", { mode }),
    card_attempt_finish: (body) => envelope(body.p_outcome === "released" ? "released" : "sent",
      { mode: body.p_mode, ...(body.p_outcome === "release_failed" ? { refusal_code: "release_failed" } : {}) }) },
  provider: { release: reply } });

async function commitFinish(mode, reply) {
  const w = startWorld(mode, reply);
  await w.run(mode === "live" ? startLive() : startTest());
  await w.settle();
  const finishes = finishOf(w);
  assert.equal(finishes.length, 1);
  return { w, body: finishes[0].body, raw: finishes[0].raw };
}

/** The finish fields hold only contract keys: an allowlisted field, the class, the anomaly code or the evidence (review CV-3). */
function assertContractKeys(fields, label) {
  for (const key of Object.keys(fields)) {
    assert.ok(Object.hasOwn(REPLY_KEY_TABLE, key) || ["provider_return_class", "anomaly_code", "dropped_fields"].includes(key),
      `${label}: ${key} is a contract key`);
  }
}

/** Every entry is exactly a {field, rule} pair of closed tokens; no value ever sits beside it. */
function assertTokens(dropped, label) {
  for (const entry of dropped) {
    assert.deepEqual(Object.keys(entry).sort(), ["field", "rule"], label);
    assert.ok(Object.hasOwn(REPLY_KEY_TABLE, entry.field), `${label}: ${entry.field}`);
    assert.ok(RULES.includes(entry.rule), `${label}: ${entry.rule}`);
  }
  assert.equal(new Set(dropped.map((entry) => entry.field)).size, dropped.length, `${label}: one entry per field`);
}

test("commit: a dropped field reaches the finish as exactly its {field, rule} tokens, never its value", async () => {
  // The finish fields of the default LIVE approval (fixtures.providerReply), written out as a literal so that each
  // case's expectation is independent of the engine's own reader and classifier (review V3-02).
  const approved = { error_flag: false, provider_return_code: 0, approval_type: "A1", phone_authorization: false,
    provider_reference: "SYN-REF-1", approval_number: "APPR1", voucher_number: "VCH1", card_last4: "4242",
    card_brand_code: "BR1", pan_entry_mode: "CHIP", payment_method_code: "CARD", provider_saved_at: "2026-10-27T10:00:05Z",
    provider_return_class: "approved" };
  const without = (fields, ...keys) => Object.fromEntries(Object.entries(fields).filter(([key]) => !keys.includes(key)));
  const drop = (...pairs) => ({ dropped_fields: pairs.map(([field, rule]) => ({ field, rule })) });
  const cases = [
    [{ SynReference: `SYN-${twelveDigits}` }, "approved",
      { ...without(approved, "provider_reference"), ...drop(["provider_reference", "digit_run"]) }, `SYN-${twelveDigits}`],
    [{ SynApprovalNumber: masked }, "approved",
      { ...without(approved, "approval_number"), ...drop(["approval_number", "masked_pattern"]) }, masked],
    [{ SynVoucher: "V 1" }, "approved", { ...without(approved, "voucher_number"), ...drop(["voucher_number", "charset"]) }, "V 1"],
    [{ SynDeposit: truncated }, "approved", { ...approved, ...drop(["deposit_id", "masked_pattern"]) }, truncated],
    [{ SynEntry: "CHIP\u0007" }, "approved",
      { ...without(approved, "pan_entry_mode"), ...drop(["pan_entry_mode", "control_character"]) }, "CHIP\u0007"],
    [{ SynBrand: "B".repeat(17) }, "approved",
      { ...without(approved, "card_brand_code"), ...drop(["card_brand_code", "length"]) }, "B".repeat(17)],
    [{ SynSavedAt: "2026-10-27T10:00:05" }, "approved",
      { ...without(approved, "provider_saved_at"), ...drop(["provider_saved_at", "format"]) }, "2026-10-27T10:00:05"],
    [{ SynApproval: "D1", SynVoucher: "V 1" }, "declined", // review ADP-3
      { ...without(approved, "voucher_number"), approval_type: "D1", provider_return_class: "declined",
        ...drop(["voucher_number", "charset"]) }, "V 1"],
    [{ SynApproval: `A1${zwsp}` }, "unknown", // an essential field: UNKNOWN (001D M2)
      { ...without(approved, "approval_type"), provider_return_class: "unclassified",
        ...drop(["approval_type", "control_character"]) }, `A1${zwsp}`],
    [{ SynTip: "5.0" }, "anomaly", // the unreadable tip stays first
      { ...approved, anomaly_code: "out_of_contract", provider_return_class: "unclassified", ...drop(["tip_amount", "format"]) }, "5.0"],
    [{ SynError: "false", SynTip: "abc", SynReference: masked }, "anomaly",
      { ...without(approved, "error_flag", "provider_reference"), anomaly_code: "out_of_contract", provider_return_class: "unclassified",
        ...drop(["error_flag", "format"], ["tip_amount", "format"], ["provider_reference", "masked_pattern"]) }, masked],
  ];
  for (const [patch, outcome, fields, value] of cases) {
    const label = JSON.stringify(patch).replaceAll(zwsp, "<U+200B>");
    const reply = providerReply(patch);
    const { w, body } = await commitFinish("live", reply);
    assert.equal(body.p_outcome, outcome, label);
    assertContractKeys(body.p_provider_fields, label);
    assert.deepEqual(body.p_provider_fields, fields, `${label}: the exact finish fields`);
    const dropped = body.p_provider_fields.dropped_fields;
    assertTokens(dropped, label);
    assert.deepEqual(dropped, extracted(reply, "live"), `${label}: exactly the reader's failures`);
    // A cross-check against the engine's own view (not an independent oracle).
    assert.deepEqual(body.p_provider_fields, expectedFields(reply, "live", "commit"), label);
    for (const entry of dropped) assert.ok(!(entry.field in body.p_provider_fields), `${label}: ${entry.field} is not also forwarded`);
    const everything = w.calls.rpc.map((call) => call.raw).join("\n");
    assert.ok(!everything.includes(JSON.stringify(value).slice(1, -1)), `${label}: the failing value never enters an RPC argument`);
  }
});

test("commit: with no failing field the classified result passes unchanged - no dropped_fields key", async () => {
  for (const mode of ["live", "test"]) {
    const reply = providerReply();
    const { body } = await commitFinish(mode, reply);
    assert.ok(!("dropped_fields" in body.p_provider_fields), mode);
    assert.deepEqual(body.p_provider_fields, expectedFields(reply, mode, "commit"), mode);
  }
  // No field of a reply that is not a readable 2xx JSON object is extracted: no field, no evidence.
  for (const reply of [() => new Response("not json", { status: 200 }), () => new Response("[1]", { status: 200 })]) {
    const { body } = await commitFinish("live", reply);
    assert.equal(body.p_outcome, "unknown");
    assert.deepEqual(body.p_provider_fields, { provider_return_class: "unclassified" });
  }
  const { body } = await commitFinish("live", () => new Response(JSON.stringify(providerReply({ SynVoucher: "V 1" })), { status: 500 }));
  assert.deepEqual(body.p_provider_fields, { provider_return_class: "error" }, "no field of a non-2xx reply is extracted");
});

test("TEST: card and provider-reference fields are never read, so never reported or forwarded; the rest is", async () => {
  const patch = { SynReference: masked, SynApprovalNumber: twelveDigits, SynVoucher: "V 1", SynDeposit: truncated,
    SynLast4: "42a2", SynBrand: "B".repeat(17), SynEntry: "CHIP\u0007", SynMethod: masked };
  const unread = [masked, twelveDigits, "V 1", truncated, "42a2", "B".repeat(17), "CHIP\u0007"];
  const quiet = await commitFinish("test", providerReply(patch));
  assert.equal(quiet.body.p_outcome, "approved");
  // Literal expectations, independent of the engine's own reader (review CT-2).
  assert.deepEqual(quiet.body.p_provider_fields, { error_flag: false, provider_return_code: 0, approval_type: "A1",
    phone_authorization: false, provider_saved_at: "2026-10-27T10:00:05Z", provider_return_class: "approved" },
  "eight failing discard fields: no evidence and no value - unread");
  const loud = await commitFinish("test", providerReply({ ...patch, SynSavedAt: "now", SynPhone: "no" }));
  assert.equal(loud.body.p_outcome, "unknown");
  assert.deepEqual(loud.body.p_provider_fields, { error_flag: false, provider_return_code: 0, approval_type: "A1",
    provider_return_class: "unclassified",
    dropped_fields: [{ field: "phone_authorization", rule: "format" }, { field: "provider_saved_at", rule: "format" }] });
  for (const run of [quiet, loud]) {
    const everything = run.w.calls.rpc.map((call) => call.raw).join("\n");
    for (const value of unread) {
      assert.ok(!everything.includes(JSON.stringify(value).slice(1, -1)), "an unread TEST value never enters an RPC argument");
    }
  }
});

test("all seventeen fields failing: seventeen entries in the profile's reply order, each field once, all six rules", async () => {
  const reply = providerReply({ SynError: "x", SynReturn: "0", SynApproval: true, SynPhone: 0, SynStatus: true,
    SynAmount: "1.0", SynCurrency: "ILSX", SynTip: "x", SynReference: masked, SynApprovalNumber: `N${twelveDigits}`,
    SynVoucher: "V 1", SynDeposit: truncated, SynLast4: "42a2", SynBrand: "B".repeat(17), SynEntry: "CHIP\u0007",
    SynMethod: masked, SynSavedAt: "now" });
  const { body } = await commitFinish("live", reply);
  assert.equal(body.p_outcome, "anomaly", "the unreadable tip decides first");
  const dropped = body.p_provider_fields.dropped_fields;
  assert.equal(dropped.length, 17);
  assert.deepEqual(dropped.map((entry) => entry.field), Object.keys(SYNTHETIC_PROFILE.reply));
  assertTokens(dropped, "all");
  assert.deepEqual([...new Set(dropped.map((entry) => entry.rule))].sort(), [...RULES].sort());
  for (const entry of dropped) if (REPLY_KEY_TABLE[entry.field].kind !== "code") assert.equal(entry.rule, "format", entry.field);
  assert.deepEqual(Object.keys(body.p_provider_fields).sort(), ["anomaly_code", "dropped_fields", "provider_return_class"]);
});

test("lookup: the evidence rides every outcome - approved, declined, not found, pending, failed and anomaly", async () => {
  // The amount is a JSON number token (DECISION D-064: a JSON string amount is a format failure).
  const found = (fields = {}) => ({ SynError: false, SynReturn: 0, SynStatus: "S1", SynAmount: numberToken("12.34"), SynCurrency: 1,
    ...fields });
  const foundFields = { error_flag: false, provider_return_code: 0, provider_status_code: "S1", provider_amount: "12.34",
    provider_currency: "ILS" };
  const voucher = [{ field: "voucher_number", rule: "charset" }];
  // [mode, reply, outcome, the exact finish fields as literals - independent of the engine's own reader and classifier
  // (review CT-1) - and the rejected raw values that must not appear in the RPC argument]
  const cases = [
    ["live", found({ SynVoucher: "V 1" }), "approved",
      { ...foundFields, provider_return_class: "approved", dropped_fields: voucher }, ["V 1"]],
    ["test", found({ SynVoucher: "V 1" }), "approved", { ...foundFields, provider_return_class: "approved" }, ["V 1"]],
    ["live", { SynError: false, SynReturn: 0, SynApproval: "D1", SynVoucher: "V 1" }, "declined", // review ADP-3
      { error_flag: false, provider_return_code: 0, approval_type: "D1", provider_return_class: "declined", dropped_fields: voucher },
      ["V 1"]],
    ["live", { SynError: true, SynReturn: -404, SynAmount: "77.7" }, "not_found",
      { error_flag: true, provider_return_code: -404, provider_return_class: "not_found",
        dropped_fields: [{ field: "provider_amount", rule: "format" }] }, ["77.7"]],
    ["live", { SynError: true, SynReturn: -404, SynAmount: "77.7", SynTip: "0.0", SynReference: `SYN-${twelveDigits}` },
      "not_found", // three entries, two essential, not in alphabetical order (reviews R5T-1, R6T-1)
      { error_flag: true, provider_return_code: -404, provider_return_class: "not_found",
        dropped_fields: [{ field: "provider_amount", rule: "format" }, { field: "tip_amount", rule: "format" },
          { field: "provider_reference", rule: "digit_run" }] },
      ["77.7", "0.0", `SYN-${twelveDigits}`]],
    ["live", { SynError: true, SynReturn: -404, SynTip: "0.0", SynBrand: "B".repeat(17) }, "not_found", // two entries (R7T-1)
      { error_flag: true, provider_return_code: -404, provider_return_class: "not_found",
        dropped_fields: [{ field: "tip_amount", rule: "format" }, { field: "card_brand_code", rule: "length" }] },
      ["0.0", "B".repeat(17)]],
    ["live", found({ SynApprovalNumber: masked }), "approved", // every rule token on the lookup path (review R7T-4)
      { ...foundFields, provider_return_class: "approved",
        dropped_fields: [{ field: "approval_number", rule: "masked_pattern" }] }, [masked]],
    ["test", { SynError: false, SynReturn: -102, SynCurrency: "bad" }, "pending",
      { error_flag: false, provider_return_code: -102, provider_return_class: "pending",
        dropped_fields: [{ field: "provider_currency", rule: "format" }] }, ["bad"]],
    ["live", { SynError: "yes", SynReturn: -77 }, "failed", { dropped_fields: [{ field: "error_flag", rule: "format" }] }, ["yes"]],
    ["live", found({ SynStatus: "S1\u0007" }), "anomaly",
      { error_flag: false, provider_return_code: 0, provider_amount: "12.34", provider_currency: "ILS",
        anomaly_code: "out_of_contract", provider_return_class: "unclassified",
        dropped_fields: [{ field: "provider_status_code", rule: "control_character" }] }, ["S1\u0007"]],
    ["live", found({ SynStatus: true }), "anomaly",
      { error_flag: false, provider_return_code: 0, provider_amount: "12.34", provider_currency: "ILS",
        anomaly_code: "out_of_contract", provider_return_class: "unclassified",
        dropped_fields: [{ field: "provider_status_code", rule: "format" }] }, []],
    ["test", found({ SynTip: "0.0" }), "anomaly",
      { ...foundFields, anomaly_code: "out_of_contract", provider_return_class: "unclassified",
        dropped_fields: [{ field: "tip_amount", rule: "format" }] }, ["0.0"]],
    ["live", found(), "approved", { ...foundFields, provider_return_class: "approved" }, []],
  ];
  for (const [mode, reply, outcome, fields, rejected] of cases) {
    const label = `${mode} ${JSON.stringify(reply)}`;
    const w = statusWorld(mode, reply);
    await w.run(statusInput());
    const [finish] = finishOf(w);
    assert.equal(finish.body.p_source, "lookup", label);
    assert.equal(finish.body.p_outcome, outcome, label);
    assertContractKeys(finish.body.p_provider_fields, label);
    assert.deepEqual(finish.body.p_provider_fields, fields, `${label}: the exact finish fields`);
    if (fields.dropped_fields) assert.deepEqual(fields.dropped_fields, extracted(reply, mode), `${label}: the reader's failures`);
    // A cross-check against the engine's own view (not an independent oracle).
    assert.deepEqual(finish.body.p_provider_fields, expectedFields(reply, mode, "lookup"), label);
    for (const value of rejected) {
      assert.ok(!finish.raw.includes(JSON.stringify(value).slice(1, -1)), `${label}: the rejected value never enters the RPC argument`);
    }
  }
  // No reply object: no field, no evidence.
  const w = statusWorld("live", () => { throw new TypeError("reset"); });
  await w.run(statusInput());
  assert.deepEqual(finishOf(w)[0].body.p_provider_fields, {});
});

test("release: the finish carries the evidence and never a provider value; the outcome rule is unchanged", async () => {
  const cases = [
    ["test", { SynError: false, SynReturn: 0 }, "released", {}],
    ["live", { SynError: false, SynReturn: 0, SynReference: "SYN-REF-9" }, "released", {}], // a readable value: never forwarded
    ["live", { SynError: false, SynReturn: 0, SynReference: "SYN-REF-9", SynVoucher: "V 1" }, "released",
      { dropped_fields: [{ field: "voucher_number", rule: "charset" }] }, ["V 1"]],
    ["live", { SynError: "no", SynReturn: 0 }, "release_failed", { dropped_fields: [{ field: "error_flag", rule: "format" }] }],
    ["test", { SynError: false, SynReturn: "0", SynSavedAt: "now" }, "release_failed",
      { dropped_fields: [{ field: "provider_return_code", rule: "format" }, { field: "provider_saved_at", rule: "format" }] }],
    ["live", { SynError: false, SynReturn: 0, SynStatus: true, SynCurrency: "bad" }, "released", // review R6T-1
      { dropped_fields: [{ field: "provider_status_code", rule: "format" }, { field: "provider_currency", rule: "format" }] },
      ["bad"]],
    ["live", { SynError: false, SynReturn: 0, SynStatus: true, SynCurrency: "bad", SynReference: `SYN-${twelveDigits}` },
      "released", // three entries (reviews R7T-2, R7T-4)
      { dropped_fields: [{ field: "provider_status_code", rule: "format" }, { field: "provider_currency", rule: "format" },
        { field: "provider_reference", rule: "digit_run" }] }, ["bad", `SYN-${twelveDigits}`]],
    ["live", { SynError: false, SynReturn: 0, SynApprovalNumber: masked, SynBrand: "B".repeat(17), SynEntry: "CHIP\u0007" },
      "released", // every rule token on the release path (review R7T-4)
      { dropped_fields: [{ field: "approval_number", rule: "masked_pattern" }, { field: "card_brand_code", rule: "length" },
        { field: "pan_entry_mode", rule: "control_character" }] }, [masked, "B".repeat(17), "CHIP\u0007"]],
    ["test", () => new Response("not json", { status: 200 }), "release_failed", {}],
  ];
  for (const [mode, reply, outcome, fields, rejected = []] of cases) {
    const label = `${mode} ${typeof reply === "function" ? "non-JSON" : JSON.stringify(reply)}`;
    const w = releaseWorld(mode, reply);
    await w.run(releaseInput());
    const [finish] = finishOf(w);
    assert.equal(finish.body.p_source, "release", label);
    assert.equal(finish.body.p_outcome, outcome, label);
    assert.deepEqual(finish.body.p_provider_fields, fields, label);
    if (typeof reply !== "function") assert.deepEqual(finish.body.p_provider_fields, expectedFields(reply, mode, "release"), label);
    assert.equal(w.calls.provider.length, 1, label);
    assert.ok(!finish.raw.includes("SYN-REF-9"), `${label}: no provider value in the release finish`);
    for (const value of rejected) {
      assert.ok(!finish.raw.includes(JSON.stringify(value).slice(1, -1)), `${label}: the rejected value never enters the RPC argument`);
    }
  }
});

test("the evidence never reaches the POS answer, even if SQL echoed it", async () => {
  const echo = (body) => ({ ...finishEcho(body), dropped_fields: body.p_provider_fields.dropped_fields ?? [] });
  const w = world({ env: LIVE_ENV, rpc: { card_attempt_context: contextOk({ attempt: contextAttempt("unknown", "live") }),
    card_attempt_adapter_read: adapterRead("unknown", "live"), card_attempt_finish: echo },
  provider: { lookup: { SynError: true, SynReturn: -404, SynVoucher: "V 1" } } });
  const out = await w.run(statusInput());
  assert.equal(out.status, 200);
  assert.ok(Array.isArray(finishOf(w)[0].body.p_provider_fields.dropped_fields));
  for (const token of ["dropped_fields", "voucher_number", "charset"]) assert.ok(!out.text.includes(token), token);
});

const REPO = new URL("../../../../", import.meta.url);
const repoText = async (path) => (await readFile(new URL(path, REPO), "utf8")).replace(/\r\n/g, "\n");
async function g1Migration() {
  const names = (await readdir(new URL("supabase/migrations/", REPO))).filter((name) => /_bizbot_zcredit_001e_drop_evidence_001\.sql$/.test(name));
  assert.equal(names.length, 1, "exactly one G1 migration");
  return repoText(`supabase/migrations/${names[0]}`);
}

test("static cross-check: the G1 migration's closed lists are the adapter's runtime reply-key table", async () => {
  const migration = await g1Migration();
  const old = await repoText("supabase/migrations/20261023225657_bizbot_zcredit_001d_server_ledger.sql");
  const handler = await repoText("supabase/functions/pos-card-charge/handler.mjs");
  // The runtime table, not a parse of its source (review ADP-1): a key added in any shape is bound here.
  const keys = Object.keys(REPLY_KEY_TABLE).sort();
  assert.equal(keys.length, 17);
  assert.deepEqual(Object.keys(profile.reply).sort(), keys, "the synthetic profile maps every allowlisted key");
  const list = (text) => [...text.matchAll(/'([a-z_0-9]+)'/g)].map((match) => match[1]);
  const sorted = (values) => [...values].sort();
  const between = (text, from, to) => { const start = text.indexOf(from); assert.ok(start >= 0, from); const end = text.indexOf(to, start + from.length); assert.ok(end > start, to); return text.slice(start + from.length, end); };
  // Block B: the field and rule sets, the format-only fields, the 17-entry bound.
  assert.deepEqual(sorted(list(between(migration, "or v_drop_field <> all (array[", "])"))), keys);
  assert.deepEqual(sorted(list(between(migration, "or v_drop_rule <> all (array[", "])"))), sorted(RULES));
  assert.deepEqual(sorted(list(between(migration, "or (v_drop_field in (", ") and v_drop_rule <> 'format')"))),
    keys.filter((key) => REPLY_KEY_TABLE[key].kind !== "code"));
  assert.match(migration, /if jsonb_array_length\(v_f -> 'dropped_fields'\) > 17 then/);
  // Block C: the essential set is the adapter's essential set without the tip, which has its own flag; the TEST
  // skip uses the 001D discard list (review ADP-7).
  const essentialSql = list(between(migration, "    if v_drop_field in (", ") then\n      v_essential_failed := true;"));
  assert.deepEqual(sorted(essentialSql), keys.filter((key) => REPLY_KEY_TABLE[key].essential && key !== "tip_amount"));
  assert.match(migration, /elsif v_drop_field = 'tip_amount' then\n {6}v_tip_failed := true;/);
  assert.equal(REPLY_KEY_TABLE.tip_amount.essential, true);
  assert.ok(migration.includes("    if a.mode = 'test' and v_drop_field = any (v_test_discard) then\n      continue;\n    end if;\n"
    + "    perform app.card_private_event_write("), "the TEST skip precedes the block C write (review CV-4)");
  const blockC = between(migration, "  for v_drop_i in 0 .. coalesce(", "  -- M3: the informational class");
  assert.ok(!/u&"/i.test(blockC), "block C uses no Unicode-escaped identifier (review R6T-2)");
  assert.equal([...blockC.matchAll(/card_private_event_write/gi)].length, 1,
    "block C names the event writer exactly once, in any letter case (reviews V3-04, R5T-2, R6T-2)");
  assert.deepEqual(sorted(list(between(migration, "v_test_discard constant text[] := array[", "];"))),
    keys.filter((key) => REPLY_KEY_TABLE[key].testDiscard), "the G1 body's own discard list (review CT-5)");
  // The same sets as the 001D body: its field loop, its essential list, its TEST discard and the event check.
  assert.deepEqual(sorted(list(between(old, "foreach v_key in array array[", "] loop"))), keys);
  assert.deepEqual(sorted(list(between(old, "      if v_key in (", ") then\n        v_essential_failed := true;"))), sorted(essentialSql));
  assert.deepEqual(sorted(list(between(old, "v_test_discard constant text[] := array[", "];"))),
    keys.filter((key) => REPLY_KEY_TABLE[key].testDiscard));
  const detail = between(old, "when 'security.card_provider_field_dropped' then array['field', 'rule', 'source']", "and (p_action <> 'test.card_recording_refused'");
  assert.deepEqual(sorted(list(between(detail, "p_detail ->> 'field' in (", ")"))), keys);
  assert.deepEqual(sorted(list(between(detail, "p_detail ->> 'rule' in (", ")"))), sorted(RULES));
  // The event's source tokens are exactly the three finish sources the handler sends (review ADP-7).
  assert.deepEqual(sorted(list(between(detail, "p_detail ->> 'source' in (", ")"))), ["commit", "lookup", "release"]);
  assert.deepEqual(sorted(new Set([...handler.matchAll(/ledger\.finish\(scope, \{ source: "([a-z]+)"/g)].map((match) => match[1]))),
    ["commit", "lookup", "release"]);
});

test("static: the G1 migration holds exactly one statement, the CREATE OR REPLACE of app.card_attempt_finish", async () => {
  const sql = await g1Migration();
  // The dollar-quoted body first (it holds its own statements and comments), then the comments outside it.
  assert.equal([...sql.matchAll(/\$\$/g)].length, 2, "one dollar-quoted body");
  const bodyless = sql.replace(/\$\$[\s\S]*?\$\$/g, "$$$$BODY$$$$");
  // Only full-line comments outside the body; with no quote, trailing comment or block comment left there, a '--'
  // cannot hide inside quotes and the lexical statement split below is exact (review CT-3).
  const outside = bodyless.split("\n").filter((line) => !/^\s*--/.test(line)).join("\n");
  assert.ok(!outside.includes("--") && !outside.includes("/*") && !outside.includes('"'), "no comment or quoted identifier");
  assert.equal([...outside.matchAll(/'/g)].length, 2, "the only literal outside the body is the empty search_path");
  assert.ok(!outside.replace("$$BODY$$", "").includes("$"), "no other dollar quote outside the body (review CV-2)");
  const statements = outside.split(";").map((statement) => statement.trim()).filter(Boolean);
  assert.equal(statements.length, 1, "exactly one top-level statement (review SQL-2)");
  assert.match(statements[0], /^create or replace function app\.card_attempt_finish\(\n/);
  assert.match(statements[0], /\n {2}returns jsonb\n {2}language plpgsql\n {2}volatile\n {2}security definer\n {2}set search_path = ''\nas \$\$BODY\$\$$/);
  assert.ok(!/\b(?:grant|revoke|alter|drop|comment|insert|update|delete|truncate|create\s+(?:table|index|policy|trigger|view|type|schema))\b/i.test(outside),
    "no other DDL, DCL or DML outside the body");
  assert.ok(!/public\.card_attempt_finish/.test(outside), "the public wrapper is not re-emitted");
});
