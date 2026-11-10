// BIZBOT-PAYMENTS-ZCREDIT-PILOT-001E: the provider engine (execution packet sections 6-7).
//
// A profile-driven JSON-over-HTTPS client. Every vendor fact - routes, request and reply field
// names, fixed request values and code tables - is a WIRE PROFILE validated against the closed
// schema below; no vendor fact is hard-coded here. API_CONTRACT section 4.55 leaves vendor names
// and codes to the owner's sealed evidence, so 001E ships no vendor profile (gate W1).
//
// Request: credential and PIN-pad values come from the attempt's frozen references, the two
// outbound keys exactly as the claim or adapter read returned them (the adapter never derives a
// key), the amount as an unquoted JSON number token from integer minor units. Reply: read with a
// byte cap as strict JSON with number tokens kept as text; ONLY the allowlisted keys of the 001D
// packet section 4.2 are extracted - no card number, BIN, expiry, token, receipt text, raw record
// or vendor message is ever read. Each value meets the SQL field rule (and, for structured fields,
// a truncated-card shape check that only drops more); a failing value is dropped here and never
// reaches an RPC argument (command-room rule G): for a 2xx reply that is a readable JSON object, only
// the {field, rule} tokens of each failing allowlisted field (its text-policy, shape or format rule)
// reach the finish as dropped_fields, where SQL writes the dropped-field event and sets the same
// essential / tip flags (DECISION D-062; nothing is recorded for a resolved, final or out-of-scope
// attempt, nor for a commit reply that arrives after the row left sent), and a failing essential value
// also fails the outcome closed here exactly as 001D's M2 does. A TEST attempt's card and
// provider-reference fields are not read at all. An amount or tip is read only as a JSON number
// token with zero, one or two fraction digits and forwarded as its canonical two-decimal text
// (DECISION D-064); SQL keeps its strict lexeme rule.
import { JsonNumber, isObject, stringifyJson } from "../json.mjs";
import { postJson } from "../http.mjs";
import { amountToken, canonicalInboundMoney, minorFromLexeme } from "../money.mjs";
import { canonicalText, safeTextFailure, textAbsent } from "../text_policy.mjs";

export class ProfileError extends Error {}
/** The request cannot be built from the configuration: nothing was sent. */
export class NotSendable extends Error {}

const NAME = /^[A-Za-z][A-Za-z0-9_]{0,63}$/;
const ROUTE = /^\/[A-Za-z0-9._~/-]{1,200}$/;
const SECRET_NAME = /^[a-z][a-z0-9_]{0,31}$/;
const INTEGER = /^-?(?:0|[1-9][0-9]{0,8})$/;
// A canonical return code: no sign on zero, no leading zero, at most six digits (SQL: +-999 999).
const RETURN_CODE = /^(?:0|-?[1-9][0-9]{0,5})$/;
const CODE_VALUE = /^[A-Za-z0-9_-]{1,16}$/;
// The outbound lexeme and the canonicalized inbound value have exactly two decimals, and the raw
// inbound grammar accepts zero to two fraction digits (DECISION D-064): only a currency with a
// minor-unit exponent of 2 is supported. The pilot charges ILS only (the Q-007 interim).
const TWO_DECIMAL_CURRENCIES = new Set(["ILS"]);

// The allowlisted reply keys (001D packet section 4.2): their kind and role.
const REPLY_KEYS = Object.freeze({
  error_flag: { kind: "boolean", essential: true },
  provider_return_code: { kind: "integer", essential: true },
  approval_type: { kind: "code", essential: true },
  phone_authorization: { kind: "boolean", essential: true },
  provider_status_code: { kind: "code", essential: true },
  provider_amount: { kind: "amount", essential: true },
  provider_currency: { kind: "currency", essential: true },
  tip_amount: { kind: "amount", essential: true },
  provider_reference: { kind: "code", testDiscard: true, reference: true },
  deposit_id: { kind: "code", testDiscard: true, reference: true },
  approval_number: { kind: "code", testDiscard: true, reference: true },
  voucher_number: { kind: "code", testDiscard: true, reference: true },
  card_last4: { kind: "code", testDiscard: true },
  card_brand_code: { kind: "code", testDiscard: true },
  pan_entry_mode: { kind: "code", testDiscard: true },
  payment_method_code: { kind: "code", testDiscard: true },
  provider_saved_at: { kind: "timestamp" },
});
const ESSENTIAL = Object.keys(REPLY_KEYS).filter((key) => REPLY_KEYS[key].essential);
/** The reply-key table as plain data for the SQL parity test of DECISION D-062 (each key's kind and role). */
export const REPLY_KEY_TABLE = Object.freeze(Object.fromEntries(Object.entries(REPLY_KEYS).map(([key, spec]) => [key,
  Object.freeze({ kind: spec.kind, essential: Boolean(spec.essential), testDiscard: Boolean(spec.testDiscard) })])));
// An amount is read only as a JSON number token (DECISION D-064): a profile cannot accept a string for it.
const ACCEPT = Object.freeze({ boolean: ["boolean", "string"], integer: ["number", "string"], code: ["string", "number"],
  amount: ["number"], currency: ["string", "number"], timestamp: ["string"] });
const SOURCES = new Set(["amount", "currency", "status_key", "duplicate_key", "pinpad", "credential", "const"]);
const RETURN_LISTS = ["return_success", "return_duplicate", "lookup_not_found", "lookup_pending"];
const VALUE_LISTS = ["approval_approved", "approval_declined", "status_approved", "status_voided", "status_refunded",
  "status_partial_refund", "status_preauthorization", "status_not_found", "status_pending"];
const STATUS_LISTS = ["status_approved", "status_voided", "status_refunded", "status_partial_refund",
  "status_preauthorization", "status_not_found", "status_pending"];
// The status-less lookup fields whose failure still reports a transaction (or an unreadable result).
const TRANSACTION_FIELDS = ["approval_type", "provider_amount", "tip_amount", "provider_return_code"];

const exactKeys = (value, required, optional = []) => isObject(value)
  && required.every((key) => Object.hasOwn(value, key))
  && Object.keys(value).every((key) => required.includes(key) || optional.includes(key));

function constant(value) {
  if (!exactKeys(value, [], ["string", "integer", "boolean", "null"]) || Object.keys(value).length !== 1) {
    throw new ProfileError("constant");
  }
  if (Object.hasOwn(value, "string")) {
    if (typeof value.string !== "string" || value.string.length > 64 || !/^[\x20-\x7e]*$/.test(value.string)) throw new ProfileError("constant");
    return value.string;
  }
  if (Object.hasOwn(value, "integer")) {
    if (typeof value.integer !== "string" || !INTEGER.test(value.integer)) throw new ProfileError("constant");
    return new JsonNumber(value.integer);
  }
  if (Object.hasOwn(value, "boolean")) {
    if (typeof value.boolean !== "boolean") throw new ProfileError("constant");
    return value.boolean;
  }
  if (value.null !== true) throw new ProfileError("constant");
  return null;
}

function requestSpecs(list, operation) {
  if (!Array.isArray(list) || list.length < 1 || list.length > 32) throw new ProfileError(`request.${operation}`);
  const names = new Set();
  const count = {};
  const specs = list.map((spec) => {
    if (!exactKeys(spec, ["name", "from"], ["value", "prefix", "secret"]) || !NAME.test(spec.name) || names.has(spec.name)
      || !SOURCES.has(spec.from)) throw new ProfileError(`request.${operation}`);
    names.add(spec.name);
    count[spec.from] = (count[spec.from] ?? 0) + 1;
    const out = { name: spec.name, from: spec.from };
    if (spec.from === "const") out.value = constant(spec.value);
    else if (Object.hasOwn(spec, "value")) throw new ProfileError(`request.${operation}`);
    if (spec.from === "pinpad" && Object.hasOwn(spec, "prefix")) {
      if (typeof spec.prefix !== "string" || !/^[A-Za-z0-9_-]{0,16}$/.test(spec.prefix)) throw new ProfileError("prefix");
      out.prefix = spec.prefix;
    } else if (Object.hasOwn(spec, "prefix")) {
      throw new ProfileError("prefix");
    }
    if (spec.from === "credential") {
      if (typeof spec.secret !== "string" || !SECRET_NAME.test(spec.secret)) throw new ProfileError("secret");
      out.secret = spec.secret;
    } else if (Object.hasOwn(spec, "secret")) {
      throw new ProfileError("secret");
    }
    return Object.freeze(out);
  });
  const exactlyOne = (source) => count[source] === 1;
  const none = (source) => !count[source];
  // The commit carries the amount, the currency, both outbound keys and the PIN pad exactly once;
  // a lookup carries the status-recovery key and never an amount; a release never an amount or key.
  const ok = operation === "commit"
    ? ["amount", "currency", "status_key", "duplicate_key", "pinpad"].every(exactlyOne)
    : operation === "lookup"
      ? exactlyOne("status_key") && none("amount") && none("currency") && none("duplicate_key")
      : exactlyOne("pinpad") && none("amount") && none("currency") && none("status_key") && none("duplicate_key");
  if (!ok || !count.credential) throw new ProfileError(`request.${operation}`);
  return Object.freeze(specs);
}

/** Validate a wire profile against the closed schema; returns it frozen or throws ProfileError. */
export function validateProfile(profile) {
  if (!exactKeys(profile, ["version", "routes", "request", "reply", "codes"])
    || typeof profile.version !== "string" || !/^[a-z0-9][a-z0-9._-]{0,63}$/.test(profile.version)) throw new ProfileError("profile");
  const { routes, request, reply, codes } = profile;
  if (!exactKeys(routes, ["commit", "lookup", "release"]) || !exactKeys(request, ["commit", "lookup", "release"])) {
    throw new ProfileError("routes");
  }
  for (const operation of ["commit", "lookup"]) {
    if (typeof routes[operation] !== "string" || !ROUTE.test(routes[operation])) throw new ProfileError("routes");
  }
  if (routes.release !== null && (typeof routes.release !== "string" || !ROUTE.test(routes.release))) throw new ProfileError("routes");
  if ((routes.release === null) !== (request.release === null)) throw new ProfileError("routes");
  const normalized = {
    version: profile.version,
    routes: Object.freeze({ commit: routes.commit, lookup: routes.lookup, release: routes.release }),
    request: Object.freeze({ commit: requestSpecs(request.commit, "commit"), lookup: requestSpecs(request.lookup, "lookup"),
      release: request.release === null ? null : requestSpecs(request.release, "release") }),
  };
  if (!isObject(reply)) throw new ProfileError("reply");
  const replyMap = Object.create(null);
  const vendorNames = new Set();
  for (const key of Object.keys(reply)) {
    const spec = reply[key];
    const kind = Object.hasOwn(REPLY_KEYS, key) ? REPLY_KEYS[key].kind : null;
    if (!kind || !exactKeys(spec, ["name", "accept"]) || !NAME.test(spec.name) || vendorNames.has(spec.name)
      || !Array.isArray(spec.accept) || spec.accept.length < 1
      || !spec.accept.every((type) => ACCEPT[kind].includes(type)) || new Set(spec.accept).size !== spec.accept.length) {
      throw new ProfileError(`reply.${key}`);
    }
    vendorNames.add(spec.name);
    replyMap[key] = Object.freeze({ name: spec.name, accept: Object.freeze([...spec.accept]) });
  }
  // Every essential classification input must be mapped (whether the vendor ever sends it is a W1 review item).
  for (const key of ESSENTIAL) if (!replyMap[key]) throw new ProfileError(`reply.${key}`);
  normalized.reply = Object.freeze(replyMap);
  if (!exactKeys(codes, [...RETURN_LISTS, ...VALUE_LISTS, "currency_request", "currency_reply"])) throw new ProfileError("codes");
  const lists = {};
  for (const list of [...RETURN_LISTS, ...VALUE_LISTS]) {
    const values = codes[list];
    const shape = RETURN_LISTS.includes(list) ? RETURN_CODE : CODE_VALUE;
    if (!Array.isArray(values) || values.length > 64 || !values.every((value) => typeof value === "string" && shape.test(value))) {
      throw new ProfileError(`codes.${list}`);
    }
    lists[list] = new Set(values);
  }
  if (lists.approval_approved.size < 1 || lists.status_approved.size < 1 || lists.return_success.size < 1) {
    throw new ProfileError("codes");
  }
  // A code means one thing: approve and decline never overlap, no status belongs to two lists, and the
  // success, duplicate, not-found and pending return codes are distinct.
  const disjoint = (a, b) => [...lists[a]].every((value) => !lists[b].has(value));
  const pairs = [["approval_approved", "approval_declined"], ["return_success", "return_duplicate"],
    ["return_success", "lookup_not_found"], ["return_success", "lookup_pending"], ["lookup_not_found", "lookup_pending"],
    ["return_duplicate", "lookup_not_found"], ["return_duplicate", "lookup_pending"]];
  for (let i = 0; i < STATUS_LISTS.length; i++) {
    for (let j = i + 1; j < STATUS_LISTS.length; j++) pairs.push([STATUS_LISTS[i], STATUS_LISTS[j]]);
  }
  for (const [a, b] of pairs) if (!disjoint(a, b)) throw new ProfileError("codes.overlap");
  if (!isObject(codes.currency_request) || !isObject(codes.currency_reply)) throw new ProfileError("currency");
  const currencyRequest = Object.create(null);
  for (const iso of Object.keys(codes.currency_request)) {
    if (!TWO_DECIMAL_CURRENCIES.has(iso)) throw new ProfileError("currency");
    currencyRequest[iso] = constant(codes.currency_request[iso]);
  }
  const currencyReply = Object.create(null);
  for (const vendor of Object.keys(codes.currency_reply)) {
    const iso = codes.currency_reply[vendor];
    if (!/^[A-Za-z0-9]{1,8}$/.test(vendor) || typeof iso !== "string" || !TWO_DECIMAL_CURRENCIES.has(iso)) throw new ProfileError("currency");
    currencyReply[vendor] = iso;
  }
  normalized.codes = Object.freeze({ ...lists, currencyRequest: Object.freeze(currencyRequest),
    currencyReply: Object.freeze(currencyReply) });
  return Object.freeze(normalized);
}

/** The secret names a profile reads from a credential record. */
export function secretNames(profile) {
  const names = new Set();
  for (const list of [profile.request.commit, profile.request.lookup, profile.request.release ?? []]) {
    for (const spec of list) if (spec.from === "credential") names.add(spec.secret);
  }
  return names;
}

// RFC 3339 with an explicit offset; a colon in the offset requires its minutes (SQL's grammar), and the
// offset is at most 15:59 (PostgreSQL's timestamptz bound). Stricter than PostgreSQL only for the
// end-of-day 24:00:00 and a leap second :60, which are refused here (dropped, never forwarded).
const RFC3339 = /^([0-9]{4})-([0-9]{2})-([0-9]{2})[Tt ]([0-9]{2}):([0-9]{2}):([0-9]{2})(?:\.[0-9]{1,9})?(?:[Zz]|([+-])([0-9]{2})(?::?([0-9]{2}))?)$/;
function validTimestamp(text) {
  const match = RFC3339.exec(text);
  if (!match) return false;
  const [year, month, day, hour, minute, second] = match.slice(1, 7).map((part) => BigInt(part));
  const leap = year % 4n === 0n && (year % 100n !== 0n || year % 400n === 0n);
  const days = month === 2n ? (leap ? 29n : 28n) : [4n, 6n, 9n, 11n].includes(month) ? 30n : 31n;
  if (year < 1n || month < 1n || month > 12n || day < 1n || day > days
    || hour > 23n || minute > 59n || second > 59n) return false;
  if (match[7] && (BigInt(match[8]) > 15n || (match[9] !== undefined && BigInt(match[9]) > 59n))) return false;
  return true;
}

// A truncated card number in a structured field, where the SQL mask rule treats '-' and '_' as
// separators, not masks: once every single '-' / '_' between two digits is removed (grouped
// renderings), a group of 4-8 digits, a run of two or more '-' / '_', then 4 digits. Adapter-only and
// stricter than SQL: it can only drop more (001D section 11 item 35, reviews B1 and LA-3). A bare
// BIN + last four, or a "mask" of one separator, stays a residual of both layers (W1 review item).
const SINGLE_SEPARATOR = /(?<=[0-9])[-_](?=[0-9])/g;
const TRUNCATED_CARD = /[0-9]{4,8}[-_]{2,}[0-9]{4}/;

/** Read one allowlisted reply key: { value } | { rule } | {} (absent). */
function readKey(reply, key, spec, codes) {
  if (!Object.hasOwn(reply, spec.name)) return {};
  const raw = reply[spec.name];
  if (raw === null || (typeof raw === "string" && textAbsent(raw))) return {};
  const accepts = (type) => spec.accept.includes(type);
  const text = typeof raw === "string" && accepts("string") ? raw
    : raw instanceof JsonNumber && accepts("number") ? raw.text : null;
  switch (REPLY_KEYS[key].kind) {
    case "boolean":
      if (typeof raw === "boolean" && accepts("boolean")) return { value: raw };
      if (typeof raw === "string" && accepts("string") && (raw === "true" || raw === "false")) return { value: raw === "true" };
      return { rule: "format" };
    case "integer":
      return text !== null && RETURN_CODE.test(text) ? { value: new JsonNumber(text) } : { rule: "format" };
    case "amount": { // inbound provider money (DECISION D-064): its canonical two-decimal text, or a format failure
      const lexeme = accepts("number") ? canonicalInboundMoney(raw) : null;
      return lexeme !== null ? { value: lexeme } : { rule: "format" };
    }
    case "currency": {
      if (text === null) return { rule: "format" };
      const iso = codes.currencyReply[text] ?? text;
      return /^[A-Z]{3}$/.test(iso) ? { value: iso } : { rule: "format" };
    }
    case "timestamp":
      return text !== null && validTimestamp(text) ? { value: text } : { rule: "format" };
    default: {
      if (text === null || (raw instanceof JsonNumber && !/^-?(?:0|[1-9][0-9]{0,15})$/.test(text))) return { rule: "format" };
      const rule = safeTextFailure(text, key);
      if (rule) return { rule };
      const canonical = canonicalText(text);
      if (key === "card_last4" && !/^[0-9]{4}$/.test(canonical)) return { rule: "charset" };
      if (TRUNCATED_CARD.test(canonical.replace(SINGLE_SEPARATOR, ""))) return { rule: "masked_pattern" };
      return { value: text };
    }
  }
}

/** Extract the allowlisted keys of one reply object. */
export function extractReply(profile, reply, { mode }) {
  const values = Object.create(null);
  const failures = [];
  for (const key of Object.keys(profile.reply)) {
    if (mode === "test" && REPLY_KEYS[key].testDiscard) continue; // discarded unread (D-057 point 8)
    const result = readKey(reply, key, profile.reply[key], profile.codes);
    if (result.rule) failures.push(Object.freeze({ field: key, rule: result.rule }));
    else if (Object.hasOwn(result, "value")) values[key] = result.value;
  }
  return { values, failures };
}

/**
 * The dropped-field evidence of one 2xx JSON-object reply (DECISION D-062): exactly the {field, rule}
 * tokens that extractReply computed - one per failing allowlisted field, in the profile's reply order,
 * never a value - added to the classified fields as dropped_fields only when a field failed, so a
 * reply with no failing field leaves the finish arguments as they were. No field of a reply that is
 * not a 2xx JSON object is extracted, so such a reply carries no evidence.
 */
function withDropped({ outcome, fields }, failures) {
  if (failures.length === 0) return { outcome, fields };
  return { outcome, fields: { ...fields, dropped_fields: failures.map(({ field, rule }) => ({ field, rule })) } };
}

const canonicalCode = (value) => (typeof value === "string" ? canonicalText(value) : null);

function providerFields(values, extra) {
  const fields = {};
  for (const key of Object.keys(values)) fields[key] = values[key];
  return { ...fields, ...extra };
}

/**
 * Commit-reply outcome (API_CONTRACT section 4.55.4; 001D packet M2). Order: an unreadable tip is
 * the out_of_contract anomaly; any other failing essential field is UNKNOWN; a phone-authorization
 * request and a duplicate refusal are UNKNOWN (never declined: the duplicate goes to the lookup
 * path); then a declined approval type; then an approval (error flag false, a success return code,
 * an approved type), whose non-zero tip is the amount_mismatch anomaly; everything else UNKNOWN.
 */
export function classifyCommit(profile, { values, failures }) {
  const failed = new Set(failures.map((failure) => failure.field));
  const codes = profile.codes;
  if (failed.has("tip_amount")) {
    return { outcome: "anomaly", fields: providerFields(values, { anomaly_code: "out_of_contract", provider_return_class: "unclassified" }) };
  }
  if ([...failed].some((field) => REPLY_KEYS[field].essential)) {
    return { outcome: "unknown", fields: providerFields(values, { provider_return_class: "unclassified" }) };
  }
  const approval = canonicalCode(values.approval_type);
  const returnCode = values.provider_return_code?.text;
  let outcome = "unknown";
  let returnClass = values.error_flag === true ? "error" : "unclassified";
  if (values.phone_authorization === true) {
    returnClass = "phone_authorization";
  } else if (returnCode !== undefined && codes.return_duplicate.has(returnCode)) {
    returnClass = "duplicate";
  } else if (approval !== null && codes.approval_declined.has(approval)) {
    outcome = "declined";
    returnClass = "declined";
  } else if (approval !== null && codes.approval_approved.has(approval) && values.error_flag === false
    && returnCode !== undefined && codes.return_success.has(returnCode)) {
    const tip = values.tip_amount === undefined ? 0n : minorFromLexeme(values.tip_amount);
    if (tip !== 0n) {
      return { outcome: "anomaly", fields: providerFields(values, { anomaly_code: "amount_mismatch", provider_return_class: "approved" }) };
    }
    outcome = "approved";
    returnClass = "approved";
  }
  return { outcome, fields: providerFields(values, { provider_return_class: returnClass }) };
}

/**
 * Lookup-reply outcome (API_CONTRACT section 4.55.5; 001D packet M2; DECISION D-063), in this precedence:
 * 1. a PRESENT status that is unreadable (its value failed the field rule) or readable but in none of the
 *    profile's status lists - after the normalization of canonicalText - is the out_of_contract anomaly,
 *    decided before any return code or approval type is read (D-063 supersedes the fallbacks of delta
 *    review LA-2 and verification V1-1). A status is ABSENT only when the reader found none (no key,
 *    JSON null or a blank string, the absent rule of D-058 point 10); no other value counts as absent;
 * 2. a readable not-found or pending reply - a listed not-found / pending status or, only when the reply
 *    carries no status, the not-found / pending return code - leaves the attempt unchanged, whatever
 *    approval type, amount or reference it also carries; a failing one is only dropped (section 4.55.5;
 *    delta review LA-1);
 * 3. a void, refund, partial-refund or pre-authorization status is its anomaly (out_of_contract when
 *    an essential field failed), never overridden by the approval type (review C-1);
 * 4. an approved status is approved, unless the approval type declines it or an essential field
 *    failed (the out_of_contract anomaly);
 * 5. with no status, a declined approval type declines when no essential field failed: the vendor has
 *    no decline status (Q-048);
 * 6. with no status, a declined type with a failing essential field and a reply reporting a transaction -
 *    an approved type, a readable amount, or an unreadable approval type, amount, tip or return code (the
 *    result field) - are the out_of_contract anomaly (reviews A4, C-4, V1-2); an unreadable flag or
 *    currency alone, and a reference (non-essential), never decide;
 * 7. anything else reports no provider fact: failed.
 */
export function classifyLookup(profile, { values, failures }) {
  const failed = new Set(failures.map((failure) => failure.field));
  const codes = profile.codes;
  const anomaly = (code) => ({ outcome: "anomaly", fields: providerFields(values,
    { anomaly_code: code, provider_return_class: "unclassified" }) });
  const concluded = (outcome) => ({ outcome, fields: providerFields(values, { provider_return_class: outcome }) });
  const status = canonicalCode(values.provider_status_code);
  const statusKnown = status !== null && STATUS_LISTS.some((list) => codes[list].has(status));
  // 1. A present status the profile cannot read or does not list decides first: no fallback overrides it.
  if (failed.has("provider_status_code") || (status !== null && !statusKnown)) return anomaly("out_of_contract");
  const essentialFailed = [...failed].some((field) => REPLY_KEYS[field].essential);
  const approval = canonicalCode(values.approval_type);
  const returnCode = values.provider_return_code?.text;
  // From here the status is listed or absent: a listed status decides; only an absent one lets the return code decide.
  const listed = (statusList, returnList) => (statusKnown ? codes[statusList].has(status)
    : returnCode !== undefined && codes[returnList].has(returnCode));
  if (listed("status_not_found", "lookup_not_found")) return concluded("not_found");
  if (listed("status_pending", "lookup_pending")) return concluded("pending");
  const declinedType = approval !== null && codes.approval_declined.has(approval);
  if (statusKnown) {
    if (codes.status_voided.has(status)) return anomaly(essentialFailed ? "out_of_contract" : "voided");
    if (codes.status_refunded.has(status)) return anomaly(essentialFailed ? "out_of_contract" : "refunded");
    if (codes.status_partial_refund.has(status)) return anomaly(essentialFailed ? "out_of_contract" : "partial_refund");
    if (codes.status_preauthorization.has(status)) return anomaly(essentialFailed ? "out_of_contract" : "preauthorization");
    if (codes.status_approved.has(status)) return declinedType || essentialFailed ? anomaly("out_of_contract") : concluded("approved");
    return anomaly("out_of_contract"); // fail closed: every listed status is decided above
  }
  // No status from here (the vendor has no decline status, Q-048).
  if (declinedType) return essentialFailed ? anomaly("out_of_contract") : concluded("declined");
  if ((approval !== null && codes.approval_approved.has(approval)) || values.provider_amount !== undefined
    || TRANSACTION_FIELDS.some((field) => failed.has(field))) return anomaly("out_of_contract");
  return { outcome: "failed", fields: {} }; // no recognizable provider fact
}

/** Release-reply outcome (API_CONTRACT section 4.55.6): confirmed only by error flag false and a success code. */
export function classifyRelease(profile, { values }) {
  const confirmed = values.error_flag === false && values.provider_return_code !== undefined
    && profile.codes.return_success.has(values.provider_return_code.text);
  return { outcome: confirmed ? "released" : "release_failed", fields: {} };
}

function buildBody(profile, specs, ctx) {
  const credential = Object.hasOwn(ctx.config.credentials, ctx.credentialRef) ? ctx.config.credentials[ctx.credentialRef] : null;
  const terminal = Object.hasOwn(ctx.config.terminals, ctx.terminalRef) ? ctx.config.terminals[ctx.terminalRef] : null;
  if (!credential || !terminal || terminal.credentialRef !== ctx.credentialRef) throw new NotSendable("references");
  const body = {};
  for (const spec of specs) {
    switch (spec.from) {
      case "amount": body[spec.name] = amountToken(ctx.amountMinor); break;
      case "currency":
        if (!Object.hasOwn(profile.codes.currencyRequest, ctx.currencyCode)) throw new NotSendable("currency");
        body[spec.name] = profile.codes.currencyRequest[ctx.currencyCode];
        break;
      case "status_key": body[spec.name] = ctx.statusKey; break;
      case "duplicate_key": body[spec.name] = ctx.duplicateKey; break;
      case "pinpad": body[spec.name] = `${spec.prefix ?? ""}${terminal.pinpadId}`; break;
      case "credential":
        if (!Object.hasOwn(credential.secret, spec.secret)) throw new NotSendable("secret");
        body[spec.name] = credential.secret[spec.secret];
        break;
      default: body[spec.name] = spec.value;
    }
  }
  return stringifyJson(body);
}

/** The provider transport for one validated profile. */
export function createProvider({ profile, fetchImpl, maxBytes }) {
  const send = async (operation, ctx, deadlineMs) => {
    const body = buildBody(profile, profile.request[operation], ctx); // throws NotSendable before any byte
    // RFC 8259 lets a reader ignore a leading byte-order mark; only the provider's replies get that leniency.
    return postJson(fetchImpl, `${ctx.config.baseUrl}${profile.routes[operation]}`, {
      "Content-Type": "application/json; charset=utf-8", "Accept": "application/json",
    }, body, { deadlineMs, maxBytes, allowBom: true });
  };
  return Object.freeze({
    version: profile.version,
    supportsRelease: profile.routes.release !== null,
    /** One commit request. Any doubt is UNKNOWN; never a retry. */
    async commit(ctx, { deadlineMs }) {
      const answer = await send("commit", ctx, deadlineMs);
      if (answer.kind !== "answer") return { outcome: "unknown", fields: {} };
      if (answer.status < 200 || answer.status > 299) return { outcome: "unknown", fields: { provider_return_class: "error" } };
      if (!isObject(answer.value)) return { outcome: "unknown", fields: { provider_return_class: "unclassified" } };
      const read = extractReply(profile, answer.value, ctx);
      return withDropped(classifyCommit(profile, read), read.failures);
    },
    /**
     * One status lookup by the stored status-recovery key. A reply that is not a readable JSON object
     * reports no provider fact (like a transport failure): the attempt is unchanged, only the lookup
     * is stamped (review A3).
     */
    async lookup(ctx, { deadlineMs }) {
      const answer = await send("lookup", ctx, deadlineMs);
      if (answer.kind !== "answer" || answer.status < 200 || answer.status > 299 || !isObject(answer.value)) {
        return { outcome: "failed", fields: {} };
      }
      const read = extractReply(profile, answer.value, ctx);
      return withDropped(classifyLookup(profile, read), read.failures);
    },
    /** One advisory release request: its fields carry the dropped-field evidence only, never a value. */
    async release(ctx, { deadlineMs }) {
      if (profile.routes.release === null) throw new NotSendable("release");
      const answer = await send("release", ctx, deadlineMs);
      if (answer.kind !== "answer" || answer.status < 200 || answer.status > 299 || !isObject(answer.value)) {
        return { outcome: "release_failed", fields: {} };
      }
      const read = extractReply(profile, answer.value, ctx);
      return withDropped(classifyRelease(profile, read), read.failures);
    },
  });
}
