// BIZBOT-PAYMENTS-ZCREDIT-PILOT-001E-W1-PROFILE-CANDIDATE-001: the unwired Z-Credit WebService PIN PAD source profile
// candidate (lib/provider/zcredit_profile.mjs; execution packet section 9). Every expectation is a literal taken from
// the accepted W1 evidence matrix (row IDs in names and messages), never from the engine's own reader. Placeholders
// only - no real host, credential, terminal, PIN-pad, key or card value: the provider is a fake transport, the suite's
// network guard refuses any real connection, and the candidate stays unwired (index.ts keeps providerProfile: null).
import "./no_network.mjs";
import test from "node:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readdir, readFile } from "node:fs/promises";
import { adapterRead, assertCleanProviderRequests, blocked, contextAttempt, contextOk, DUPLICATE_KEY, envelope, freshClaim,
  LIVE_ENV, PROVIDER_BASE, providerConfig, QUERY_KEY, releaseInput, REST, settleAll, startLive, startTest, statusInput,
  stray, SYNTHETIC_PROFILE, world } from "./fixtures.mjs";
import { createProvider, extractReply, NotSendable, ProfileError, secretNames, validateProfile }
  from "../lib/provider/engine.mjs";
import { providerConfiguration } from "../lib/config.mjs";
import { LIMITS } from "../lib/constants.mjs";
import { parseJson, stringifyJson } from "../lib/json.mjs";
import { ZCREDIT_PROFILE_CANDIDATE as CANDIDATE } from "../lib/provider/zcredit_profile.mjs";

test.after(async () => { await settleAll(); assert.deepEqual(blocked, []); assert.deepEqual(stray, []); });

const FUNCTION_DIR = new URL("../", import.meta.url);
const read = async (url) => (await readFile(url, "utf8")).replace(/\r\n/g, "\n");
const clone = (value) => JSON.parse(JSON.stringify(value));
const profile = validateProfile(CANDIDATE);

const ESSENTIAL = ["error_flag", "provider_return_code", "approval_type", "phone_authorization", "provider_status_code",
  "provider_amount", "provider_currency", "tip_amount"];
const OPTIONAL = ["provider_reference", "deposit_id", "approval_number", "voucher_number", "card_last4", "card_brand_code",
  "pan_entry_mode", "payment_method_code", "provider_saved_at"];
const APPROVAL_LISTS = ["approval_approved", "approval_declined"];
const RETURN_LISTS = ["return_success", "return_duplicate", "lookup_not_found", "lookup_pending"];
const STATUS_LISTS = ["status_approved", "status_voided", "status_refunded", "status_partial_refund", "status_preauthorization",
  "status_not_found", "status_pending"];
// Vendor members the matrix keeps unmapped (E2-05, E2-16, E2-32, E4-01 .. E4-11): never a reply name.
const UNMAPPED_MEMBERS = ["ReturnMessage", "IsTelAuthAbilty", "ReferenceNumber", "ApprovalNumber", "VoucherNumber", "DepositID",
  "Card4Digits", "CardNumber", "CardBIN", "ExpDate_MMYY", "Token", "HolderID", "CardName", "CardIssuerCode", "CardFinancerCode",
  "CardBrandCode", "PanEntryMode", "PaymentMethod", "SaveDate", "ClientReciept", "SellerReciept", "ResultRecord", "IntOt",
  "IntOt_JSON", "DealTypeCode", "CreditTypeCode", "J", "NumberOfPayments", "FirstPaymentSum", "OtherPaymentsSum",
  "CustomerName", "CustomerAddress", "CustomerEmail", "CustomerPhone", "ExtraInfo", "ItemDescription", "IsCustomerPresent"];

// ---------------------------------------------------------------------------------------------------------------------
// 1. Schema

test("schema: the candidate passes the closed validator and is exactly the FACT-row profile of the packet", () => {
  assert.deepEqual(Object.keys(CANDIDATE), ["version", "routes", "request", "reply", "codes"]);
  assert.equal(profile.version, "zcredit-ws-pinpad-candidate-1");
  assert.deepEqual(clone(CANDIDATE.routes), { commit: "/Transaction/CommitFullTransaction", // E1-04
    lookup: "/Transaction/GetTransactionStatusByTransactionUniqueIdForQuery", // E1-05
    release: "/Transaction/ReleasePinpad" }); // E1-07
  const terminal = { name: "TerminalNumber", from: "credential", secret: "terminal_number" }; // E1-08
  const password = { name: "Password", from: "credential", secret: "password" }; // E1-09
  const track2 = { name: "Track2", from: "pinpad", prefix: "PINPAD" }; // E1-11, E1-31
  assert.deepEqual(clone(CANDIDATE.request), {
    commit: [terminal, password, track2,
      { name: "CardNumber", from: "const", value: { string: "" } }, // E1-14
      { name: "ExpDate_MMYY", from: "const", value: { string: "" } }, // E1-14
      { name: "TransactionSum", from: "amount" }, // E1-16
      { name: "TransactionType", from: "const", value: { string: "01" } }, // E1-18
      { name: "CurrencyType", from: "currency" }, // E1-17
      { name: "CreditType", from: "const", value: { integer: "1" } }, // E1-19
      { name: "NumberOfPayments", from: "const", value: { integer: "1" } }, // E1-20
      { name: "J", from: "const", value: { integer: "0" } }, // E1-22
      { name: "IsCustomerPresent", from: "const", value: { boolean: true } }, // E1-23
      { name: "AuthNum", from: "const", value: { string: "" } }, // E1-28
      { name: "TransactionUniqueIdForQuery", from: "status_key" }, // E1-24
      { name: "TransactionUniqueID", from: "duplicate_key" }, // E1-25
      { name: "UseAdvancedDuplicatesCheck", from: "const", value: { boolean: false } }], // E1-26
    lookup: [terminal, password, { name: "UniqueQuery", from: "status_key" }], // E1-30
    release: [terminal, password, track2], // E1-31
  });
  assert.deepEqual(clone(CANDIDATE.reply), {
    error_flag: { name: "HasError", accept: ["boolean"] }, // E2-03
    provider_return_code: { name: "ReturnCode", accept: ["number"] }, // E2-04
    approval_type: { name: "ApprovalType", accept: ["string"] }, // E2-09
    phone_authorization: { name: "IsTelApprovalNeeded", accept: ["boolean"] }, // E2-15
    provider_status_code: { name: "StatusCode", accept: ["number"] }, // E2-17
    provider_amount: { name: "TransactionSum", accept: ["number"] }, // E2-26
    provider_currency: { name: "CurrencyTypeCode", accept: ["number"] }, // E2-27
    tip_amount: { name: "TipAmount", accept: ["number"] }, // E2-30
  });
  assert.deepEqual(clone(CANDIDATE.codes), {
    approval_approved: ["1", "3", "03", "5", "8"], // E2-10
    approval_declined: ["2", "4", "6"], // E2-11
    return_success: ["0"], // E2-04, E2-06
    return_duplicate: ["-88001", "-88002"], // E2-07, E2-08
    lookup_not_found: [], lookup_pending: [], // E2-24 (UNKNOWN)
    status_approved: ["1", "2"], status_voided: ["3"], status_refunded: ["4"], status_partial_refund: ["6"], // E2-18 .. E2-21
    status_preauthorization: ["900", "901", "902", "903", "904"], // E2-22
    status_not_found: [], status_pending: [], // E2-23 (UNKNOWN)
    currency_request: { ILS: { integer: "1" } }, // E1-17, E5-01
    currency_reply: { 1: "ILS" }, // E2-27, E5-02
  });
  assert.deepEqual([...secretNames(profile)].sort(), ["password", "terminal_number"], "member names of the credential record only");
});

test("schema: the eight essential reply keys are mapped, and no optional E4 key or never-mapped vendor member is", () => {
  assert.deepEqual(Object.keys(CANDIDATE.reply), ESSENTIAL);
  for (const key of OPTIONAL) assert.ok(!Object.hasOwn(CANDIDATE.reply, key), `${key} stays unmapped (E4)`);
  const names = Object.values(CANDIDATE.reply).map((spec) => spec.name);
  for (const member of UNMAPPED_MEMBERS) assert.ok(!names.includes(member), `${member} is never a reply name`);
  for (const key of ESSENTIAL) {
    const copy = clone(CANDIDATE);
    delete copy.reply[key];
    assert.throws(() => validateProfile(copy), ProfileError, `the validator requires ${key}`);
  }
});

test("schema: disjoint code lists, exactly the documented decline forms, empty not-found / pending lists, ILS only", () => {
  const codes = CANDIDATE.codes;
  // Each domain's lists are pairwise disjoint (an approval type, a return code and a status are different fields).
  for (const domain of [APPROVAL_LISTS, RETURN_LISTS, STATUS_LISTS]) {
    for (let i = 0; i < domain.length; i++) {
      assert.equal(new Set(codes[domain[i]]).size, codes[domain[i]].length, `${domain[i]} lists each value once`);
      for (let j = i + 1; j < domain.length; j++) {
        assert.ok(codes[domain[i]].every((value) => !codes[domain[j]].includes(value)), `${domain[i]} / ${domain[j]}`);
      }
    }
  }
  for (const list of ["return_duplicate", "lookup_not_found", "lookup_pending"]) {
    assert.ok(!codes[list].includes("0"), `the success code is not in ${list}`);
  }
  assert.deepEqual([...codes.approval_declined], ["2", "4", "6"], "E2-11: the documented decline forms only");
  assert.deepEqual([...codes.approval_approved], ["1", "3", "03", "5", "8"], "E2-10");
  for (const padded of ["01", "02", "04", "05", "06", "08"]) {
    for (const list of [...APPROVAL_LISTS, ...RETURN_LISTS, ...STATUS_LISTS]) {
      assert.ok(!codes[list].includes(padded), `no undocumented padded form ${padded} in ${list} (E2-12)`);
    }
  }
  for (const value of ["0", "7"]) assert.ok(!APPROVAL_LISTS.some((list) => codes[list].includes(value)), `E2-13: ${value} is neither`);
  for (const list of ["lookup_not_found", "lookup_pending", "status_not_found", "status_pending"]) {
    assert.deepEqual([...codes[list]], [], `${list} stays empty: nothing is documented (E2-23, E2-24)`);
  }
  assert.deepEqual(Object.keys(profile.codes.currencyRequest), ["ILS"]);
  assert.deepEqual({ ...profile.codes.currencyReply }, { 1: "ILS" });
  // The closed validator refuses an overlap with the success code and any currency but ILS.
  const mutations = [
    (p) => { p.codes.return_duplicate.push("0"); }, (p) => { p.codes.lookup_not_found.push("0"); },
    (p) => { p.codes.lookup_pending.push("0"); }, (p) => { p.codes.approval_declined.push("1"); },
    (p) => { p.codes.status_voided.push("1"); }, (p) => { p.codes.currency_request = { USD: { integer: "2" } }; },
    (p) => { p.codes.currency_reply = { 1: "ILS", 2: "USD" }; }, (p) => { p.codes.currency_reply = { 3: "EUR" }; },
    (p) => { p.reply.provider_amount.accept = ["number", "string"]; }, (p) => { p.reply.tip_amount.accept = ["string"]; },
  ];
  for (const [index, mutate] of mutations.entries()) {
    const copy = clone(CANDIDATE);
    mutate(copy);
    assert.throws(() => validateProfile(copy), ProfileError, `mutation ${index}`);
  }
});

test("schema: the candidate is deeply frozen - no importer can change it", () => {
  assert.throws(() => { CANDIDATE.routes.commit = "/elsewhere"; }, TypeError);
  assert.throws(() => { CANDIDATE.codes.approval_declined.push("02"); }, TypeError);
  assert.throws(() => { CANDIDATE.request.commit[2].prefix = "PinPad"; }, TypeError);
  assert.throws(() => { CANDIDATE.reply.tip_amount.accept.push("string"); }, TypeError);
  assert.throws(() => { CANDIDATE.codes.currency_request.ILS.integer = "2"; }, TypeError);
  assert.throws(() => { CANDIDATE.extra = 1; }, TypeError);
});

// ---------------------------------------------------------------------------------------------------------------------
// 2. Request bytes (placeholders only)

// A configuration a wired candidate would need: each credential record carries the two members the candidate names.
// Every value is a non-sensitive placeholder; the base URL is the suite's synthetic host.
function candidateConfig(overrides = {}) {
  return providerConfig({
    credentials: {
      "cred-test": { mode: "test", scope: "development",
        secret: { terminal_number: "SYNTHETIC-TERMINAL-TEST", password: "SYNTHETIC-PASSWORD-TEST" } },
      "cred-live": { mode: "live", scope: "merchant", restaurant_id: REST,
        secret: { terminal_number: "SYNTHETIC-TERMINAL-LIVE", password: "SYNTHETIC-PASSWORD-LIVE" } },
    },
    terminals: {
      "pad-test": { credential_ref: "cred-test", pinpad_id: "SYNTHETIC-PINPAD-TEST" },
      "pad-live": { credential_ref: "cred-live", pinpad_id: "SYNTHETIC-PINPAD-LIVE" },
    },
    ...overrides,
  });
}
const CANDIDATE_ENV = Object.freeze({ POS_CARD_PROVIDER_CONFIG: JSON.stringify(candidateConfig()) });
const CANDIDATE_LIVE_ENV = Object.freeze({ POS_CARD_PROVIDER_CONFIG: JSON.stringify(candidateConfig({ environment: "production" })) });
const config = providerConfiguration((name) => (name === "POS_CARD_PROVIDER_CONFIG" ? CANDIDATE_ENV.POS_CARD_PROVIDER_CONFIG : undefined));
const HEADERS = { "Content-Type": "application/json; charset=utf-8", "Accept": "application/json" };

/** The candidate behind a capturing fake transport that answers raw JSON bytes with the documented status 201 (E2-01). */
function capture(text = '{"HasError":false,"ReturnCode":0}') {
  const requests = [];
  const fetchImpl = async (url, init) => {
    requests.push({ url, method: init.method, headers: { ...init.headers }, body: init.body });
    return new Response(text, { status: 201, headers: { "content-type": "application/json" } });
  };
  return { requests, provider: createProvider({ profile, fetchImpl, maxBytes: LIMITS.providerReplyBytes }) };
}
const context = (mode, extra = {}) => ({ config, terminalRef: `pad-${mode}`, credentialRef: `cred-${mode}`, mode, ...extra });
const commitContext = (mode = "test", extra = {}) => context(mode, { statusKey: QUERY_KEY, duplicateKey: DUPLICATE_KEY,
  amountMinor: 1234n, currencyCode: "ILS", ...extra });

// The commit members in the candidate's order (the accepted redacted request fixture's order, E1-35), TEST placeholders.
const COMMIT_MEMBERS = Object.freeze(['"TerminalNumber":"SYNTHETIC-TERMINAL-TEST"', '"Password":"SYNTHETIC-PASSWORD-TEST"',
  '"Track2":"PINPADSYNTHETIC-PINPAD-TEST"', '"CardNumber":""', '"ExpDate_MMYY":""', '"TransactionSum":12.34',
  '"TransactionType":"01"', '"CurrencyType":1', '"CreditType":1', '"NumberOfPayments":1', '"J":0', '"IsCustomerPresent":true',
  '"AuthNum":""', '"TransactionUniqueIdForQuery":"abcdefghijklmnopabcdefgh"', '"TransactionUniqueID":"ponmlkjihgfedcbaponmlkji"',
  '"UseAdvancedDuplicatesCheck":false']);
const bodyOf = (members) => `{${members.join(",")}}`;
const COMMIT_BODY = bodyOf(COMMIT_MEMBERS);
const LOOKUP_BODY = '{"TerminalNumber":"SYNTHETIC-TERMINAL-TEST","Password":"SYNTHETIC-PASSWORD-TEST","UniqueQuery":"abcdefghijklmnopabcdefgh"}';
const RELEASE_BODY = '{"TerminalNumber":"SYNTHETIC-TERMINAL-TEST","Password":"SYNTHETIC-PASSWORD-TEST","Track2":"PINPADSYNTHETIC-PINPAD-TEST"}';

test("request bytes: the commit carries exactly the documented members and constants (E1-08 .. E1-28)", async () => {
  assert.equal(QUERY_KEY, "abcdefghijklmnopabcdefgh");
  assert.equal(DUPLICATE_KEY, "ponmlkjihgfedcbaponmlkji");
  const { requests, provider } = capture('{"HasError":false,"ReturnCode":0,"ApprovalType":"1","IsTelApprovalNeeded":false}');
  assert.equal((await provider.commit(commitContext(), { deadlineMs: 1000 })).outcome, "approved");
  assert.deepEqual(requests, [{ url: `${PROVIDER_BASE}/Transaction/CommitFullTransaction`, method: "POST", headers: HEADERS,
    body: COMMIT_BODY }]);
  const members = Object.keys(parseJson(requests[0].body));
  assert.deepEqual(members, ["TerminalNumber", "Password", "Track2", "CardNumber", "ExpDate_MMYY", "TransactionSum",
    "TransactionType", "CurrencyType", "CreditType", "NumberOfPayments", "J", "IsCustomerPresent", "AuthNum",
    "TransactionUniqueIdForQuery", "TransactionUniqueID", "UseAdvancedDuplicatesCheck"]);
  // Omitted on purpose: CVV (E1-15), the Tip object (E1-27), the installment sums (E1-21), PINPAD_ID (it travels in
  // Track2, E1-13), any KEY (E1-10) and the personal or option members (E1-29).
  for (const absent of ["CVV", "Tip", "FirstPaymentSum", "OtherPaymentsSum", "PINPAD_ID", "KEY", "Key", "HolderID", "CustomerName"]) {
    assert.ok(!members.includes(absent), absent);
  }
  // A LIVE commit reads the LIVE attempt's own frozen records.
  const live = capture('{"HasError":false,"ReturnCode":0,"ApprovalType":"1","IsTelApprovalNeeded":false}');
  await live.provider.commit(commitContext("live"), { deadlineMs: 1000 });
  assert.equal(live.requests[0].body, COMMIT_BODY.replaceAll("-TEST", "-LIVE"));
});

test("request bytes: the amount is always the canonical X.XX number token (E1-16, E5-06; D-052 point 4)", async () => {
  for (const [minor, lexeme] of [[1n, "0.01"], [100n, "1.00"], [1200n, "12.00"], [1230n, "12.30"], [1234n, "12.34"],
    [5000n, "50.00"], [99999999999n, "999999999.99"]]) {
    const { requests, provider } = capture();
    await provider.commit(commitContext("test", { amountMinor: minor }), { deadlineMs: 1000 });
    assert.equal(requests[0].body, bodyOf(COMMIT_MEMBERS.map((member) => (member.startsWith('"TransactionSum":')
      ? `"TransactionSum":${lexeme}` : member))), lexeme);
  }
});

test("request bytes: the lookup and the release carry exactly their documented members (E1-30, E1-31, E1-32)", async () => {
  const lookup = capture('{"HasError":true,"ReturnCode":-97}');
  await lookup.provider.lookup(context("test", { statusKey: QUERY_KEY }), { deadlineMs: 1000 });
  assert.deepEqual(lookup.requests, [{ url: `${PROVIDER_BASE}/Transaction/GetTransactionStatusByTransactionUniqueIdForQuery`,
    method: "POST", headers: HEADERS, body: LOOKUP_BODY }]);
  const release = capture('{"HasError":false,"ReturnCode":0}');
  await release.provider.release(context("test"), { deadlineMs: 1000 });
  assert.deepEqual(release.requests, [{ url: `${PROVIDER_BASE}/Transaction/ReleasePinpad`, method: "POST", headers: HEADERS,
    body: RELEASE_BODY }]);
});

test("request bytes: a currency the candidate cannot encode is NotSendable before any byte (E1-17, E5-07)", async () => {
  for (const currencyCode of ["USD", "EUR", "JPY"]) {
    const { requests, provider } = capture();
    await assert.rejects(provider.commit(commitContext("live", { currencyCode }), { deadlineMs: 1000 }), NotSendable, currencyCode);
    assert.deepEqual(requests, [], `${currencyCode}: nothing was sent`);
  }
});

// ---------------------------------------------------------------------------------------------------------------------
// 3. Replies (raw bytes through the candidate and the engine)

/** One operation answered with `text`; the fields as the finish receives them (number tokens as numbers). */
async function reply(operation, text, mode = "live") {
  const { requests, provider } = capture(text);
  const extra = operation === "commit" ? { statusKey: QUERY_KEY, duplicateKey: DUPLICATE_KEY, amountMinor: 1234n, currencyCode: "ILS" }
    : operation === "lookup" ? { statusKey: QUERY_KEY } : {};
  const result = await provider[operation](context(mode, extra), { deadlineMs: 1000 });
  assert.equal(requests.length, 1, `${operation}: one request`);
  return { outcome: result.outcome, fields: JSON.parse(stringifyJson(result.fields)) };
}
const APPROVE = '"HasError":false,"ReturnCode":0,"ApprovalType":"1","IsTelApprovalNeeded":false';
const approved = (extra = {}) => ({ outcome: "approved", fields: { error_flag: false, provider_return_code: 0, approval_type: "1",
  phone_authorization: false, ...extra, provider_return_class: "approved" } });
const FOUND = '"HasError":false,"ReturnCode":0,"TransactionSum":12.34,"CurrencyTypeCode":1';
const found = (status, extra = {}) => ({ error_flag: false, provider_return_code: 0, provider_status_code: status,
  provider_amount: "12.34", provider_currency: "ILS", ...extra });
const OOC = { anomaly_code: "out_of_contract", provider_return_class: "unclassified" };

test("replies: the documented approved values approve and the documented declined values decline (E2-06, E2-10, E2-11)", async () => {
  for (const type of ["1", "3", "03", "5", "8"]) {
    assert.deepEqual(await reply("commit", `{"HasError":false,"ReturnCode":0,"ApprovalType":"${type}","IsTelApprovalNeeded":false}`),
      { outcome: "approved", fields: { error_flag: false, provider_return_code: 0, approval_type: type, phone_authorization: false,
        provider_return_class: "approved" } }, type);
  }
  for (const type of ["2", "4", "6"]) {
    // RC-02's shape: the error envelope with a Shva code; the listed declined type decides, never the code.
    assert.deepEqual(await reply("commit", `{"HasError":true,"ReturnCode":4,"ApprovalType":"${type}","IsTelApprovalNeeded":false}`),
      { outcome: "declined", fields: { error_flag: true, provider_return_code: 4, approval_type: type, phone_authorization: false,
        provider_return_class: "declined" } }, type);
    assert.equal((await reply("commit", `{"HasError":false,"ReturnCode":0,"ApprovalType":"${type}"}`)).outcome, "declined", type);
  }
  // An approval needs the error flag false AND the success code (E2-06).
  assert.deepEqual(await reply("commit", '{"HasError":true,"ReturnCode":0,"ApprovalType":"1","IsTelApprovalNeeded":false}'),
    { outcome: "unknown", fields: { error_flag: true, provider_return_code: 0, approval_type: "1", phone_authorization: false,
      provider_return_class: "error" } });
  assert.equal((await reply("commit", '{"HasError":false,"ReturnCode":10,"ApprovalType":"1"}')).outcome, "unknown", "10: partial approval");
});

test("replies: undocumented approval forms and the neither-list values stay UNKNOWN (E2-12, E2-13)", async () => {
  for (const type of ["0", "7", "01", "02", "04", "05", "06", "08", "9", "00", "A"]) {
    assert.deepEqual(await reply("commit", `{"HasError":false,"ReturnCode":0,"ApprovalType":"${type}","IsTelApprovalNeeded":false}`),
      { outcome: "unknown", fields: { error_flag: false, provider_return_code: 0, approval_type: type, phone_authorization: false,
        provider_return_class: "unclassified" } }, type);
  }
  // A type sent as a number is no documented form (E2-09: a string): a failing essential field, UNKNOWN.
  assert.deepEqual(await reply("commit", '{"HasError":false,"ReturnCode":0,"ApprovalType":3}'), { outcome: "unknown",
    fields: { error_flag: false, provider_return_code: 0, provider_return_class: "unclassified",
      dropped_fields: [{ field: "approval_type", rule: "format" }] } });
});

test("replies: a duplicate refusal is UNKNOWN for the lookup path, never declined (E2-07, E2-08)", async () => {
  for (const code of [-88001, -88002]) {
    assert.deepEqual(await reply("commit", `{"HasError":true,"ReturnCode":${code},"ReturnMessage":"SYNTHETIC MESSAGE"}`),
      { outcome: "unknown", fields: { error_flag: true, provider_return_code: code, provider_return_class: "duplicate" } }, String(code));
    assert.equal((await reply("commit", `{"HasError":true,"ReturnCode":${code},"ApprovalType":"2"}`)).fields.provider_return_class,
      "duplicate", `${code} beside a declined type`);
  }
});

test("replies: the phone flag and a positive return code alone never decline (E2-14, E2-15, E2-29)", async () => {
  // RC-03: phone authorization in play.
  assert.deepEqual(await reply("commit", '{"HasError":true,"ReturnCode":3,"ReturnMessage":"SYNTHETIC MESSAGE","IsTelApprovalNeeded":true}'),
    { outcome: "unknown", fields: { error_flag: true, provider_return_code: 3, phone_authorization: true,
      provider_return_class: "phone_authorization" } });
  // The flag beside an otherwise approvable reply is UNKNOWN as well, never approved.
  assert.deepEqual(await reply("commit", '{"HasError":false,"ReturnCode":0,"ApprovalType":"1","IsTelApprovalNeeded":true}'),
    { outcome: "unknown", fields: { error_flag: false, provider_return_code: 0, approval_type: "1", phone_authorization: true,
      provider_return_class: "phone_authorization" } });
  // 10 partial approval, 41 / 42 J2 required, 280 timeout, 500 stopped by the user, 3 / 4 phone triggers; -97 input error.
  for (const code of [10, 41, 42, 280, 500, 3, 4, -97]) {
    assert.deepEqual(await reply("commit", `{"HasError":true,"ReturnCode":${code}}`),
      { outcome: "unknown", fields: { error_flag: true, provider_return_code: code, provider_return_class: "error" } }, String(code));
  }
});

test("replies: every mapped member is read only in its documented JSON type; any other type fails closed (E2-03 .. E2-30)", async () => {
  const dropped = (field) => ({ dropped_fields: [{ field, rule: "format" }] });
  // Commit: a failing essential field is UNKNOWN, never approved (an unreadable tip is the anomaly, below).
  assert.deepEqual(await reply("commit", '{"HasError":"false","ReturnCode":0,"ApprovalType":"1","IsTelApprovalNeeded":false}'),
    { outcome: "unknown", fields: { provider_return_code: 0, approval_type: "1", phone_authorization: false,
      provider_return_class: "unclassified", ...dropped("error_flag") } }, "HasError as a string (E2-03: boolean)");
  assert.deepEqual(await reply("commit", '{"HasError":false,"ReturnCode":"0","ApprovalType":"1","IsTelApprovalNeeded":false}'),
    { outcome: "unknown", fields: { error_flag: false, approval_type: "1", phone_authorization: false,
      provider_return_class: "unclassified", ...dropped("provider_return_code") } }, "ReturnCode as a string (E2-04: integer)");
  assert.deepEqual(await reply("commit", '{"HasError":false,"ReturnCode":0,"ApprovalType":"1","IsTelApprovalNeeded":"false"}'),
    { outcome: "unknown", fields: { error_flag: false, provider_return_code: 0, approval_type: "1",
      provider_return_class: "unclassified", ...dropped("phone_authorization") } }, "IsTelApprovalNeeded as a string (E2-15: boolean)");
  // Lookup: a found reply whose currency is not the documented integer is the out_of_contract anomaly (E2-27).
  assert.deepEqual(await reply("lookup", '{"HasError":false,"ReturnCode":0,"StatusCode":1,"TransactionSum":12.34,"CurrencyTypeCode":"1"}'),
    { outcome: "anomaly", fields: { error_flag: false, provider_return_code: 0, provider_status_code: "1", provider_amount: "12.34",
      ...OOC, ...dropped("provider_currency") } }, "CurrencyTypeCode as a string (E2-27: integer)");
  // Release: a return code in another type never confirms (E2-28).
  assert.deepEqual(await reply("release", '{"HasError":false,"ReturnCode":"0"}'),
    { outcome: "release_failed", fields: dropped("provider_return_code") });
});

test("replies: a J2 query code 42 beside HasError false is no success - never approved, never a confirmed release (E2-14)", async () => {
  // E2-14: 42 ("a J2 query is required") also arrives with HasError false on a successful J2 check; only 0 is success.
  assert.deepEqual(await reply("commit", '{"HasError":false,"ReturnCode":42,"ApprovalType":"1","IsTelApprovalNeeded":false}'),
    { outcome: "unknown", fields: { error_flag: false, provider_return_code: 42, approval_type: "1", phone_authorization: false,
      provider_return_class: "unclassified" } });
  assert.deepEqual(await reply("release", '{"HasError":false,"ReturnCode":42}'), { outcome: "release_failed", fields: {} });
});

test("replies: the documented statuses decide; any other present status is out_of_contract (E2-17 .. E2-22; D-063)", async () => {
  for (const status of ["1", "2"]) {
    assert.deepEqual(await reply("lookup", `{${FOUND},"StatusCode":${status}}`),
      { outcome: "approved", fields: { ...found(status), provider_return_class: "approved" } }, status);
  }
  for (const [status, code] of [["3", "voided"], ["4", "refunded"], ["6", "partial_refund"], ["900", "preauthorization"],
    ["901", "preauthorization"], ["902", "preauthorization"], ["903", "preauthorization"], ["904", "preauthorization"]]) {
    assert.deepEqual(await reply("lookup", `{${FOUND},"StatusCode":${status}}`),
      { outcome: "anomaly", fields: { ...found(status), anomaly_code: code, provider_return_class: "unclassified" } }, status);
  }
  for (const status of ["0", "5", "7", "8", "99", "100", "899", "905", "1000", "-1"]) {
    assert.deepEqual(await reply("lookup", `{${FOUND},"StatusCode":${status}}`),
      { outcome: "anomaly", fields: { ...found(status), ...OOC } }, `unlisted ${status}`);
  }
  // A status sent in any other form is unreadable: out_of_contract before any fallback, its value never forwarded.
  for (const status of ['"1"', '"2"', "1.0", "true", "[1]", "{}"]) {
    const out = await reply("lookup", `{${FOUND},"StatusCode":${status}}`);
    assert.deepEqual(out, { outcome: "anomaly", fields: { error_flag: false, provider_return_code: 0, provider_amount: "12.34",
      provider_currency: "ILS", ...OOC, dropped_fields: [{ field: "provider_status_code", rule: "format" }] } }, status);
  }
});

test("replies: an absent status (no key, null, blank) stays distinct from an unknown one (D-058 point 10; D-063)", async () => {
  for (const status of [undefined, "null", '""', '" "', `"${String.fromCodePoint(0x3000)}"`]) {
    const member = status === undefined ? "" : `,"StatusCode":${status}`;
    assert.deepEqual(await reply("lookup", `{"HasError":true,"ReturnCode":-97${member}}`), { outcome: "failed", fields: {} },
      `absent ${status}: no provider fact`);
    assert.deepEqual(await reply("lookup", `{"HasError":false,"ReturnCode":0,"TransactionSum":12.34${member}}`),
      { outcome: "anomaly", fields: { error_flag: false, provider_return_code: 0, provider_amount: "12.34", ...OOC } },
      `absent ${status} with a readable amount: a transaction, out_of_contract`);
  }
  // An unknown present status is never absent.
  assert.equal((await reply("lookup", '{"HasError":true,"ReturnCode":-97,"StatusCode":5}')).fields.anomaly_code, "out_of_contract");
  // The engine's absent-status decline (D-063 point 3) is kept, though the documented lookup reply has no approval type (E2-25).
  assert.deepEqual(await reply("lookup", '{"HasError":true,"ReturnCode":4,"ApprovalType":"2"}'),
    { outcome: "declined", fields: { error_flag: true, provider_return_code: 4, approval_type: "2", provider_return_class: "declined" } });
});

test("replies: a zero tip under D-064 - absent is no tip, 0 is 0.00, a string is refused (E2-30, E2-31)", async () => {
  for (const tip of [undefined, "null", '""', '" "']) {
    const member = tip === undefined ? "" : `,"TipAmount":${tip}`;
    assert.deepEqual(await reply("commit", `{${APPROVE}${member}}`), approved(), `absent ${tip}: never 0.00`);
  }
  for (const tip of ["0", "0.0", "0.00"]) {
    assert.deepEqual(await reply("commit", `{${APPROVE},"TipAmount":${tip}}`), approved({ tip_amount: "0.00" }), tip);
  }
  for (const tip of ['"0"', '"0.00"', '"12.30"', "0.000", "-0", "1e0", "-5"]) {
    assert.deepEqual(await reply("commit", `{${APPROVE},"TipAmount":${tip}}`), { outcome: "anomaly",
      fields: { error_flag: false, provider_return_code: 0, approval_type: "1", phone_authorization: false, ...OOC,
        dropped_fields: [{ field: "tip_amount", rule: "format" }] } }, tip);
  }
  for (const [tip, lexeme] of [["5", "5.00"], ["5.5", "5.50"], ["0.01", "0.01"]]) {
    assert.deepEqual(await reply("commit", `{${APPROVE},"TipAmount":${tip}}`), { outcome: "anomaly",
      fields: { error_flag: false, provider_return_code: 0, approval_type: "1", phone_authorization: false, tip_amount: lexeme,
        anomaly_code: "amount_mismatch", provider_return_class: "approved" } }, tip);
  }
});

test("replies: whole and one-decimal echoed amounts under D-064 (E2-26, E5-03)", async () => {
  for (const [token, lexeme] of [["12", "12.00"], ["12.0", "12.00"], ["12.3", "12.30"], ["12.30", "12.30"], ["10.35", "10.35"],
    ["0", "0.00"], ["999999999.99", "999999999.99"]]) {
    assert.deepEqual(await reply("lookup", `{"HasError":false,"ReturnCode":0,"StatusCode":1,"TransactionSum":${token},"CurrencyTypeCode":1}`),
      { outcome: "approved", fields: { ...found("1", { provider_amount: lexeme }), provider_return_class: "approved" } }, token);
  }
  for (const token of ["12.345", "12.300", "1e2", "-12", "1000000000", '"12.34"', '"12"']) {
    assert.deepEqual(await reply("lookup", `{"HasError":false,"ReturnCode":0,"StatusCode":1,"TransactionSum":${token},"CurrencyTypeCode":1}`),
      { outcome: "anomaly", fields: { error_flag: false, provider_return_code: 0, provider_status_code: "1", provider_currency: "ILS",
        ...OOC, dropped_fields: [{ field: "provider_amount", rule: "format" }] } }, token);
  }
  // A reply currency other than the mapped 1 (ILS) is dropped and fails a found lookup closed (E5-02, E5-07).
  for (const currency of ["2", "3", '"1"']) {
    assert.equal((await reply("lookup", `{"HasError":false,"ReturnCode":0,"StatusCode":1,"TransactionSum":12.34,"CurrencyTypeCode":${currency}}`))
      .fields.anomaly_code, "out_of_contract", currency);
  }
});

test("replies: the other operations' not-found codes never conclude not-found or pending (E2-24; Q-048)", async () => {
  // -844 (refund), -9011 (CompleteJ5Transaction), Shva 443 (a cancel) and 257 (no operation named), and RC-10's -9000.
  for (const code of [-844, -9011, 443, 257, -9000]) {
    assert.deepEqual(await reply("lookup", `{"HasError":true,"ReturnCode":${code},"ReturnMessage":"SYNTHETIC MESSAGE"}`),
      { outcome: "failed", fields: {} }, `${code}: no provider fact, the attempt unchanged`);
    assert.deepEqual(await reply("lookup", `{"HasError":true,"ReturnCode":${code},"TransactionSum":12.34}`),
      { outcome: "anomaly", fields: { error_flag: true, provider_return_code: code, provider_amount: "12.34", ...OOC } },
      `${code} with a readable amount: never not_found`);
  }
});

test("replies: a release is confirmed only by HasError false and ReturnCode 0 (E2-28; RX-03, RC-10)", async () => {
  assert.deepEqual(await reply("release", '{"HasError":false,"ReturnCode":0,"ReturnMessage":""}'), { outcome: "released", fields: {} });
  for (const text of ['{"HasError":true,"ReturnCode":-9000,"ReturnMessage":"SYNTHETIC MESSAGE"}', '{"HasError":false,"ReturnCode":-9000}',
    '{"HasError":true,"ReturnCode":0}', '{"ReturnCode":0}', '{"HasError":false}', "{}"]) {
    assert.deepEqual(await reply("release", text), { outcome: "release_failed", fields: {} }, text);
  }
  assert.deepEqual(await reply("release", '{"HasError":"false","ReturnCode":0}'),
    { outcome: "release_failed", fields: { dropped_fields: [{ field: "error_flag", rule: "format" }] } });
});

// The documented examples' shapes (RX-01 commit, RX-02 lookup) with synthetic values in every member the candidate never
// maps; the lookup's own phone flag is set true to show that it is not read (E2-16).
const RX01 = '{"HasError":false,"ReturnCode":0,"ReturnMessage":"","CardNumber":"SYNTHETIC-CARD-FIELD","Card4Digits":"SYNTHETIC-LAST",' +
  '"CardBIN":"SYNTHETIC-BIN","ExpDate_MMYY":"SYNTHETIC-EXPIRY","CardName":"SYNTHETIC CARD NAME","CardIssuerCode":1,' +
  '"CardFinancerCode":2,"CardBrandCode":2,"ReferenceNumber":"SYNTHETIC-REFERENCE","VoucherNumber":"SYNTHETIC-VOUCHER",' +
  '"ApprovalNumber":"SYNTHETIC-APPROVAL","IsTelApprovalNeeded":false,"Token":"SYNTHETIC-TOKEN","ClientReciept":"",' +
  '"SellerReciept":"","ResultRecord":"","IntOt_JSON":"","IntOt":"","PanEntryMode":"05","PaymentMethod":2,"ApprovalType":"03"}';
const RX02 = '{"HasError":false,"ReturnCode":0,"ReturnMessage":"","IsTelAuthAbilty":true,"ReferenceNumber":"SYNTHETIC-REFERENCE",' +
  '"ClientReciept":"","SellerReciept":"","ApprovalNumber":"SYNTHETIC-APPROVAL","CardBrandCode":2,"CardFinancerCode":2,' +
  '"CardIssuerCode":1,"CardName":"SYNTHETIC CARD NAME","CardNumber":"SYNTHETIC-LAST","ExpDate_MMYY":"SYNTHETIC-EXPIRY",' +
  '"Token":"SYNTHETIC-TOKEN","VoucherNumber":"SYNTHETIC-VOUCHER","SaveDate":"2019-03-04T21:06:37","TransactionSum":10.35,' +
  '"NumberOfPayments":1,"FirstPaymentSum":0,"OtherPaymentsSum":0,"J":0,"HolderID":"SYNTHETIC-HOLDER","IsCustomerPresent":false,' +
  '"CustomerName":"SYNTHETIC NAME","CustomerAddress":"SYNTHETIC ADDRESS","CustomerEmail":"SYNTHETIC-MAILBOX",' +
  '"DealTypeCode":"01","CreditTypeCode":1,"CurrencyTypeCode":1,"CustomerPhone":"SYNTHETIC-PHONE","ExtraInfo":"SYNTHETIC TEXT",' +
  '"ItemDescription":"SYNTHETIC TEXT","DepositID":"SYNTHETIC-DEPOSIT","StatusCode":2,"PanEntryMode":"05","PaymentMethod":2}';

test("replies: the documented examples classify, and no unmapped member is read or changes an outcome (E2-05, E2-16, E2-32, E4)", async () => {
  for (const mode of ["live", "test"]) {
    assert.deepEqual(await reply("commit", RX01, mode), { outcome: "approved", fields: { error_flag: false, provider_return_code: 0,
      approval_type: "03", phone_authorization: false, provider_return_class: "approved" } }, `RX-01 ${mode}`);
    assert.deepEqual(await reply("lookup", RX02, mode), { outcome: "approved", fields: { error_flag: false, provider_return_code: 0,
      provider_status_code: "2", provider_amount: "10.35", provider_currency: "ILS", provider_return_class: "approved" } },
    `RX-02 ${mode}`);
    // Only the eight mapped names are ever touched; the reply is never enumerated.
    for (const text of [RX01, RX02]) {
      const touched = new Set();
      const proxy = new Proxy(parseJson(text), {
        get(target, key) { touched.add(String(key)); return target[key]; },
        getOwnPropertyDescriptor(target, key) { touched.add(String(key)); return Reflect.getOwnPropertyDescriptor(target, key); },
        has(target, key) { touched.add(String(key)); return key in target; },
        ownKeys() { throw new Error("the reply is never enumerated"); },
      });
      extractReply(profile, proxy, { mode });
      assert.deepEqual([...touched].sort(), ["ApprovalType", "CurrencyTypeCode", "HasError", "IsTelApprovalNeeded", "ReturnCode",
        "StatusCode", "TipAmount", "TransactionSum"], mode);
    }
  }
  // Removing every unmapped member changes nothing.
  const mapped = (text) => {
    const value = parseJson(text);
    return `{${Object.values(CANDIDATE.reply).map((spec) => spec.name).filter((name) => Object.hasOwn(value, name))
      .map((name) => `"${name}":${stringifyJson(value[name])}`).join(",")}}`;
  };
  assert.deepEqual(await reply("commit", mapped(RX01)), await reply("commit", RX01));
  assert.deepEqual(await reply("lookup", mapped(RX02)), await reply("lookup", RX02));
});

// ---------------------------------------------------------------------------------------------------------------------
// 4. Through the handler (the scripted world routes the candidate's own paths; no real host)

const raw201 = (text) => () => new Response(text, { status: 201, headers: { "content-type": "application/json" } });
const finishOf = (w) => w.calls.rpc.filter((call) => call.name === "card_attempt_finish");

test("handler: a TEST commit approval with TipAmount 0 reaches the finish once, as 0.00 (D-064)", async () => {
  const w = world({ profile: CANDIDATE, env: CANDIDATE_ENV, rpc: { card_attempt_context: contextOk(), card_attempt_claim: freshClaim(),
    card_attempt_finish: envelope("approved") },
  provider: { commit: raw201('{"HasError":false,"ReturnCode":0,"ApprovalType":"03","IsTelApprovalNeeded":false,"TipAmount":0}') } });
  const out = await w.run(startTest());
  await w.settle();
  assert.equal(out.status, 200);
  assert.deepEqual(w.calls.provider.map((call) => [call.op, call.url, call.raw]),
    [["commit", `${PROVIDER_BASE}/Transaction/CommitFullTransaction`, COMMIT_BODY]]);
  assertCleanProviderRequests(assert, w);
  const finishes = finishOf(w);
  assert.equal(finishes.length, 1);
  assert.equal(finishes[0].body.p_source, "commit");
  assert.equal(finishes[0].body.p_outcome, "approved");
  assert.deepEqual(finishes[0].body.p_provider_fields, { error_flag: false, provider_return_code: 0, approval_type: "03",
    phone_authorization: false, tip_amount: "0.00", provider_return_class: "approved" });
});

test("handler: a lookup of a whole-shekel echo reaches the finish as 12.00, the lookup's phone flag unread (D-064, E2-16)", async () => {
  const w = world({ profile: CANDIDATE, env: CANDIDATE_ENV, rpc: {
    card_attempt_context: contextOk({ attempt: contextAttempt("unknown", "test", { amount_minor: 1200 }) }),
    card_attempt_adapter_read: adapterRead("unknown", "test", { amount_minor: 1200 }), card_attempt_finish: envelope("approved") },
  provider: { lookup: raw201('{"HasError":false,"ReturnCode":0,"IsTelAuthAbilty":true,"StatusCode":1,"TransactionSum":12,"CurrencyTypeCode":1}') } });
  const out = await w.run(statusInput());
  assert.equal(out.status, 200);
  assert.deepEqual(w.calls.provider.map((call) => [call.op, call.url, call.raw]),
    [["lookup", `${PROVIDER_BASE}/Transaction/GetTransactionStatusByTransactionUniqueIdForQuery`, LOOKUP_BODY]]);
  assertCleanProviderRequests(assert, w);
  const [finish] = finishOf(w);
  assert.equal(finish.body.p_source, "lookup");
  assert.equal(finish.body.p_outcome, "approved");
  assert.deepEqual(finish.body.p_provider_fields, { error_flag: false, provider_return_code: 0, provider_status_code: "1",
    provider_amount: "12.00", provider_currency: "ILS", provider_return_class: "approved" });
});

test("handler: a release confirmed by HasError false and ReturnCode 0 carries no provider value (E2-28)", async () => {
  const w = world({ profile: CANDIDATE, env: CANDIDATE_ENV, rpc: { card_attempt_context: contextOk({ attempt: contextAttempt("sent") }),
    card_attempt_adapter_read: adapterRead("sent"), card_attempt_mark_release_requested: envelope("sent"),
    card_attempt_finish: envelope("released") }, provider: { release: raw201('{"HasError":false,"ReturnCode":0,"ReturnMessage":""}') } });
  const out = await w.run(releaseInput());
  assert.equal(out.status, 200);
  assert.deepEqual(w.calls.provider.map((call) => [call.op, call.url, call.raw]),
    [["release", `${PROVIDER_BASE}/Transaction/ReleasePinpad`, RELEASE_BODY]]);
  const [finish] = finishOf(w);
  assert.equal(finish.body.p_source, "release");
  assert.equal(finish.body.p_outcome, "released");
  assert.deepEqual(finish.body.p_provider_fields, {});
});

// ---------------------------------------------------------------------------------------------------------------------
// 5. The two tests carried from the W1 decision (the W1-LOOKUP-SAFETY-001 packet section 8)

test("carried W1 (section 8.2): a LIVE start in an unsupported currency is refused before any RPC call or provider request", async () => {
  for (const [label, worldProfile, env] of [["candidate", CANDIDATE, CANDIDATE_LIVE_ENV], ["synthetic", SYNTHETIC_PROFILE, LIVE_ENV]]) {
    for (const currency of ["USD", "EUR"]) {
      const w = world({ profile: worldProfile, env, rpc: {} }); // any RPC call would be unscripted, so a stray
      const out = await w.run(startLive({ currency_code: currency }));
      assert.equal(out.status, 503, `${label} ${currency}`);
      assert.deepEqual(out.body, { ok: false, error: "provider_unavailable" }, `${label} ${currency}`);
      assert.deepEqual(w.calls.rpc, [], `${label} ${currency}: no context proof, no claim`);
      assert.deepEqual(w.calls.provider, [], `${label} ${currency}: no provider request`);
    }
    // Control: the same LIVE start in ILS passes step (1) and reaches the context proof (refused here, so nothing more).
    const control = world({ profile: worldProfile, env, rpc: { card_attempt_context: { ok: false, error: "permission_denied" } } });
    assert.deepEqual((await control.run(startLive())).body, { ok: false, error: "permission_denied" }, label);
    assert.deepEqual(control.rpcNames(), ["card_attempt_context"], label);
    assert.deepEqual(control.calls.provider, [], label);
  }
});

// The deployment / retention guard (packet section 8): the module's source text and three projections of its data are
// pinned - the whole data, what recovery reads, and the credential record members every operation needs.
const canonical = (value) => (Array.isArray(value) ? `[${value.map(canonical).join(",")}]`
  : value !== null && typeof value === "object"
    ? `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${canonical(value[key])}`).join(",")}}`
    : JSON.stringify(value));
const digest = (value) => createHash("sha256").update(canonical(value)).digest("hex");
/** What the lookup and release of an unresolved attempt READ: everything but the commit route, the commit request specs,
 * the version and the two commit-only lists (code lists compared as sets). */
const recovery = (p) => ({
  routes: { lookup: p.routes.lookup, release: p.routes.release },
  request: { lookup: p.request.lookup, release: p.request.release },
  reply: p.reply,
  codes: Object.fromEntries(Object.keys(p.codes).filter((list) => !["return_duplicate", "currency_request"].includes(list))
    .map((list) => [list, Array.isArray(p.codes[list]) ? [...p.codes[list]].sort() : p.codes[list]])),
});
/** The credential record members any operation names. The handler requires all of them before every start
 * (compatible()) and before every lookup and release of an existing attempt (servable()), so a change of this set is a
 * configuration-order change. Computed from the raw profile, not through the engine's secretNames. */
const credentialMembers = (p) => [...new Set(["commit", "lookup", "release"].flatMap((op) => (p.request[op] ?? [])
  .filter((spec) => spec.from === "credential").map((spec) => spec.secret)))].sort();
const PINNED = Object.freeze({ version: "zcredit-ws-pinpad-candidate-1",
  source: "dbf69edc93a026b8003e9ae4ae76d660c3f5b84050fa76e38ceb0444b03fee84", // SHA-256 of the module's LF text
  whole: "f5e49075d6d6ed6a806cbb85ecfc25d9ca26293d6e759f993212efb0c06a116b",
  recovery: "c2b40af94df69a242b88bc52bb496bfbe9cc89d0ec899bba25171ca5e6ff249a",
  credentialMembers: Object.freeze(["password", "terminal_number"]) });
const GATE = "packet section 8: an incompatible profile cannot replace the candidate while any attempt is sent, unknown or "
  + "released without a resolution";
const CONFIGURATION_ORDER = "packet section 8: every credential record must carry a new member before the profile is deployed";

test("carried W1 (section 8.1): the deployment / retention guard pins the candidate; a recovery change is incompatible", async () => {
  const source = await read(new URL("lib/provider/zcredit_profile.mjs", FUNCTION_DIR));
  assert.equal(createHash("sha256").update(source).digest("hex"), PINNED.source,
    `the module changed (its data, comments or helper): review it and update the pins in the same change (${GATE})`);
  assert.equal(CANDIDATE.version, PINNED.version, `the version changed: pin it with the digests in one reviewed change (${GATE})`);
  assert.equal(digest(CANDIDATE), PINNED.whole,
    `the candidate's data changed: update the digest pins in one reviewed change, with a new version by review (${GATE})`);
  assert.equal(digest(recovery(CANDIDATE)), PINNED.recovery, `the recovery projection changed - an incompatible change (${GATE})`);
  assert.deepEqual(credentialMembers(CANDIDATE), PINNED.credentialMembers, `the credential members changed (${CONFIGURATION_ORDER})`);
  // Commit-only changes move the whole digest and keep the recovery projection: compatible with unresolved attempts.
  const compatible = [
    (p) => { p.version = "zcredit-ws-pinpad-candidate-2"; },
    (p) => { p.routes.commit = "/Transaction/CommitFullTransactionNext"; },
    (p) => { p.request.commit.find((spec) => spec.name === "NumberOfPayments").value = { integer: "2" }; },
    (p) => { p.request.commit = p.request.commit.filter((spec) => spec.name !== "AuthNum"); },
    (p) => { p.codes.return_duplicate = ["-88001"]; },
    (p) => { p.codes.status_preauthorization = [...p.codes.status_preauthorization].reverse(); }, // a reorder of a set
  ];
  for (const [index, mutate] of compatible.entries()) {
    const copy = clone(CANDIDATE);
    mutate(copy);
    assert.notEqual(digest(copy), PINNED.whole, `compatible ${index}: still visible to the pin`);
    assert.equal(digest(recovery(copy)), PINNED.recovery, `compatible ${index}`);
    assert.deepEqual(credentialMembers(copy), PINNED.credentialMembers, `compatible ${index}: the same credential members`);
  }
  // A credential member added to or renamed in the commit alone keeps what recovery reads, but lookups and releases of
  // existing attempts check every member too: a configuration-order change (the KEY of section 7.2 would be one).
  const memberChanges = [
    (p) => { p.request.commit.splice(2, 0, { name: "Key", from: "credential", secret: "key" }); },
    (p) => { p.request.commit[1].secret = "terminal_password"; },
  ];
  for (const [index, mutate] of memberChanges.entries()) {
    const copy = clone(CANDIDATE);
    mutate(copy);
    assert.equal(digest(recovery(copy)), PINNED.recovery, `member change ${index}: recovery reads the same fields`);
    assert.notDeepEqual(credentialMembers(copy), PINNED.credentialMembers, `member change ${index}: ${CONFIGURATION_ORDER}`);
  }
  // Anything a lookup or release reads moves the recovery projection: an incompatible replacement.
  const incompatible = [
    (p) => { p.routes.lookup = "/Transaction/GetTransactionStatusByReferenceId"; },
    (p) => { p.routes.release = "/Transaction/ReleasePinPad"; },
    (p) => { p.request.lookup[2].name = "TransactionUniqueIdForQuery"; },
    (p) => { p.request.lookup[0].secret = "terminal"; },
    (p) => { p.request.release[2].prefix = "PinPad"; },
    (p) => { p.reply.provider_status_code.name = "Status"; },
    (p) => { p.reply.provider_amount.accept = ["number", "number"]; },
    (p) => { p.codes.status_approved = ["1"]; },
    (p) => { p.codes.status_voided = ["3", "5"]; },
    (p) => { p.codes.lookup_not_found = ["-844"]; },
    (p) => { p.codes.lookup_pending = ["-9011"]; },
    (p) => { p.codes.approval_declined = ["2", "4", "6", "02"]; },
    (p) => { p.codes.return_success = ["0", "42"]; },
    (p) => { p.codes.currency_reply = { 1: "ILS", 2: "ILS" }; },
  ];
  for (const [index, mutate] of incompatible.entries()) {
    const copy = clone(CANDIDATE);
    mutate(copy);
    assert.notEqual(digest(recovery(copy)), PINNED.recovery, `incompatible ${index}`);
  }
});

// ---------------------------------------------------------------------------------------------------------------------
// 6. Static guards

async function files(dir, prefix = "") {
  const out = [];
  for (const entry of await readdir(dir, { withFileTypes: true })) {
    const name = `${prefix}${entry.name}`;
    if (entry.isDirectory()) out.push(...await files(new URL(`${entry.name}/`, dir), `${name}/`));
    else out.push(name);
  }
  return out;
}
const withoutComments = (text) => text.split("\n").filter((line) => !/^\s*(?:\/\/|\/\*\*|\*)/.test(line))
  .map((line) => line.replace(/\s+\/\/ .*$/, "")).join("\n");

test("static: the module is plain data - no import, URL, host, value, long digit run, logging or runtime access", async () => {
  const source = await read(new URL("lib/provider/zcredit_profile.mjs", FUNCTION_DIR));
  const code = withoutComments(source);
  // Every string literal of the code is double-quoted, so the allowlist below sees all of them, and no comment survives
  // the strip (no single quote, backtick, block comment or line comment is left in the code).
  assert.ok(!/['`]|\/\*|\/\//.test(code), "a literal that is not double-quoted, or an unstripped comment");
  assert.ok(!/\bimport\b|\brequire\s*\(/.test(code), "it imports nothing");
  assert.equal([...code.matchAll(/\bexport\b/g)].length, 1, "one export");
  assert.match(code, /^export const ZCREDIT_PROFILE_CANDIDATE = frozen\(\{$/m);
  for (const forbidden of [/https?:/i, /:\/\//, /\bwww\./i, /\.co\.il\b/i, /\.(?:com|net|org|io|test)\b/i, /zcredit\.co/i, /apiary/i,
    /\bpci\b/i, /base_?url/i]) {
    assert.ok(!forbidden.test(source), `no URL or host: ${forbidden}`);
  }
  assert.ok(!/[0-9](?:[ .,_-]?[0-9]){6,}/.test(source), "no card-shaped or identifier-shaped digit run, separators included");
  assert.ok(!/PINPAD[A-Za-z0-9]/i.test(source), "no PIN-pad identifier after the prefix");
  assert.ok(!/\bconsole\b|\bDeno\b|EdgeRuntime|\bfetch\b|\bprocess\b|globalThis|\bnew Function\b|\beval\b/.test(code),
    "no logging, network or runtime access");
  // Every string literal of the code (double-quoted, asserted above) is a documented name, constant or code, or one of
  // the two BIZBOT-internal names, so no value can hide in a literal. Comments are reviewed prose: the checks above scan
  // them, with the whole source, for URL and host shapes, long or separated digit runs and PIN-pad identifiers, and the
  // deployment guard's source pin makes every comment edit a reviewed change.
  const literals = new Set([...code.matchAll(/"((?:[^"\\]|\\.)*)"/g)].map((match) => match[1]));
  const expected = new Set(["zcredit-ws-pinpad-candidate-1", "terminal_number", "password", "credential", "const", "pinpad",
    "amount", "currency", "status_key", "duplicate_key", "PINPAD", "", "01", "1", "0", "3", "03", "5", "8", "2", "4", "6",
    "-88001", "-88002", "900", "901", "902", "903", "904", "ILS", "boolean", "number", "string", "object",
    ...Object.values(CANDIDATE.routes), ...Object.keys(CANDIDATE.reply).map((key) => CANDIDATE.reply[key].name),
    ...["commit", "lookup", "release"].flatMap((op) => CANDIDATE.request[op].map((spec) => spec.name))]);
  assert.deepEqual([...literals].filter((literal) => !expected.has(literal)), [], "an unexpected string literal");
});

test("static: unwired - index.ts keeps providerProfile null and imports only the handler; only this test imports the candidate", async () => {
  const index = await read(new URL("index.ts", FUNCTION_DIR));
  assert.deepEqual([...index.matchAll(/^import .* from "([^"]+)";$/gm)].map((match) => match[1]), ["./handler.mjs"]);
  assert.match(index, /^ {2}providerProfile: null,$/m);
  assert.ok(!/zcredit_profile|ZCREDIT_PROFILE_CANDIDATE/.test(index), "index.ts names no candidate");
  const names = await files(FUNCTION_DIR);
  const importers = [];
  for (const name of names.filter((file) => /\.(mjs|ts)$/.test(file))) {
    const text = await read(new URL(name, FUNCTION_DIR));
    if (/from\s+["'][^"']*zcredit_profile\.mjs["']|import\(\s*["'][^"']*zcredit_profile/.test(text)) importers.push(name);
    if (!name.startsWith("test/") && name !== "lib/provider/zcredit_profile.mjs") {
      assert.ok(!/zcredit_profile|ZCREDIT_PROFILE_CANDIDATE/.test(text), `${name} refers to the candidate`);
    }
  }
  assert.deepEqual(importers, ["test/zcredit_profile.test.mjs"]);
  // No runtime configuration can select a profile: the handler takes one only as a constructor option (null by default),
  // and the configuration parser knows no profile.
  const handler = await read(new URL("handler.mjs", FUNCTION_DIR));
  assert.match(handler, /providerProfile = null,/);
  assert.ok(!/profile/i.test(withoutComments(await read(new URL("lib/config.mjs", FUNCTION_DIR)))), "config.mjs reads no profile");
});

test("static: no SQL, migration, configuration or CI file refers to the candidate", async () => {
  // That none of them changed is proven by the review package (its diff of the branch); here: none can wire or name it.
  const REPO = new URL("../../../../", import.meta.url);
  const paths = ["supabase/config.toml", ".github/workflows/ci.yml"];
  for (const dir of ["supabase/migrations/", "supabase/tests/"]) {
    paths.push(...(await files(new URL(dir, REPO))).filter((name) => name.endsWith(".sql")).map((name) => `${dir}${name}`));
  }
  assert.ok(paths.length > 10, `${paths.length} files read`);
  for (const path of paths) {
    assert.ok(!/zcredit_profile|ZCREDIT_PROFILE_CANDIDATE|zcredit-ws-pinpad/i.test(await read(new URL(path, REPO))), path);
  }
});
