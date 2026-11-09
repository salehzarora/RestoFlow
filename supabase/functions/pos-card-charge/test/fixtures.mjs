// Synthetic fixtures for the pos-card-charge suite: a scripted fake PostgREST (the seven card
// RPCs), a scripted fake provider driven by an obviously synthetic wire profile, and request
// builders. Every identifier, key, credential and amount is synthetic; no real host is used
// (`.test` names only) and test/no_network.mjs refuses any real connection. Any request to an
// unexpected host and any unscripted RPC or provider operation is recorded in `stray`, which every
// test file asserts empty, so a call the handler swallows still fails the suite.
import { blocked } from "./no_network.mjs";
import { createHandler } from "../handler.mjs";

export { blocked };
export const stray = [];
/** Every background task of every world, so a file's after-hook can let them settle before it checks `stray`. */
const allTasks = [];
export const settleAll = () => Promise.allSettled(allTasks);

export const BASE = "https://synthetic-project.supabase.test";
export const PROVIDER_BASE = "https://synthetic-provider.test/api";
export const JWT = "synthetic.caller.jwt";
export const ANON = "synthetic-public-anon-key-0001";
export const SERVICE = "synthetic-service-only-key-0001";

/** Synthetic UUIDs whose digit runs stay short (letters between them). */
export const id = (n, version = "4") => `e1e1e1e1-e1e1-${version}e1e-8e1e-e1e1e1e1${n.toString(16).padStart(4, "0")}`;
export const ORG = id(1);
export const REST = id(2);
export const BRANCH = id(3);
export const DEVICE = id(4);
export const OTHER_DEVICE = id(5);
export const PIN = id(6);
export const CALLER = id(7); // the native transport principal (an auth.users id)
export const EMPLOYEE = id(8); // the PIN employee - never the binding
export const MEMBERSHIP = id(9);
export const ATTEMPT = id(10);
export const ORDER = id(11);
export const ROW = id(12);
export const PAYMENT = id(13);
export const TOKEN = "synthetic-device-session-token";
export const QUERY_KEY = "abcdefghijklmnopabcdefgh";
export const DUPLICATE_KEY = "ponmlkjihgfedcbaponmlkji";
export const TS = "2026-10-27T10:00:00.123456+00:00";

export const SYNTHETIC_PROFILE = Object.freeze({
  version: "synthetic-wire-v1",
  routes: { commit: "/synthetic/commit", lookup: "/synthetic/lookup", release: "/synthetic/release" },
  request: {
    commit: [
      { name: "syn_terminal", from: "credential", secret: "terminal" },
      { name: "syn_password", from: "credential", secret: "password" },
      { name: "syn_pad", from: "pinpad", prefix: "PAD" },
      { name: "syn_amount", from: "amount" },
      { name: "syn_currency", from: "currency" },
      { name: "syn_kind", from: "const", value: { string: "regular" } },
      { name: "syn_installments", from: "const", value: { integer: "1" } },
      { name: "syn_present", from: "const", value: { boolean: true } },
      { name: "syn_status_key", from: "status_key" },
      { name: "syn_duplicate_key", from: "duplicate_key" },
    ],
    lookup: [
      { name: "syn_terminal", from: "credential", secret: "terminal" },
      { name: "syn_password", from: "credential", secret: "password" },
      { name: "syn_query", from: "status_key" },
    ],
    release: [
      { name: "syn_terminal", from: "credential", secret: "terminal" },
      { name: "syn_password", from: "credential", secret: "password" },
      { name: "syn_pad", from: "pinpad", prefix: "PAD" },
    ],
  },
  reply: {
    error_flag: { name: "SynError", accept: ["boolean"] },
    provider_return_code: { name: "SynReturn", accept: ["number"] },
    approval_type: { name: "SynApproval", accept: ["string"] },
    phone_authorization: { name: "SynPhone", accept: ["boolean"] },
    provider_status_code: { name: "SynStatus", accept: ["string", "number"] },
    provider_amount: { name: "SynAmount", accept: ["number"] }, // amounts: a number token only (DECISION D-064)
    provider_currency: { name: "SynCurrency", accept: ["string", "number"] },
    tip_amount: { name: "SynTip", accept: ["number"] },
    provider_reference: { name: "SynReference", accept: ["string"] },
    approval_number: { name: "SynApprovalNumber", accept: ["string"] },
    voucher_number: { name: "SynVoucher", accept: ["string"] },
    deposit_id: { name: "SynDeposit", accept: ["string"] },
    card_last4: { name: "SynLast4", accept: ["string"] },
    card_brand_code: { name: "SynBrand", accept: ["string", "number"] },
    pan_entry_mode: { name: "SynEntry", accept: ["string"] },
    payment_method_code: { name: "SynMethod", accept: ["string"] },
    provider_saved_at: { name: "SynSavedAt", accept: ["string"] },
  },
  codes: {
    approval_approved: ["A1", "A2"],
    approval_declined: ["D1", "D2"],
    return_success: ["0"],
    return_duplicate: ["-901"],
    lookup_not_found: ["-404"],
    lookup_pending: ["-102"],
    status_approved: ["S1", "S2"],
    status_voided: ["S3"],
    status_refunded: ["S4"],
    status_partial_refund: ["S6"],
    status_preauthorization: ["S9"],
    status_not_found: ["S0"],
    status_pending: ["S5"],
    currency_request: { ILS: { integer: "1" } },
    currency_reply: { 1: "ILS" },
  },
});

export const providerConfig = (overrides = {}) => ({
  environment: "test",
  base_url: PROVIDER_BASE,
  key_format: "alpha16-l24-v1",
  credentials: {
    "cred-test": { mode: "test", scope: "development", secret: { terminal: "SYNTERM", password: "SYNPASS-TEST" } },
    "cred-live": { mode: "live", scope: "merchant", restaurant_id: REST, secret: { terminal: "SYNLIVE", password: "SYNPASS-LIVE" } },
  },
  terminals: {
    "pad-test": { credential_ref: "cred-test", pinpad_id: "SYNPAD1" },
    "pad-live": { credential_ref: "cred-live", pinpad_id: "SYNPAD2" },
  },
  ...overrides,
});

/** The environment override of a LIVE world: the production configuration (SQL refuses LIVE in 'test'). */
export const LIVE_ENV = Object.freeze({ POS_CARD_PROVIDER_CONFIG: JSON.stringify(providerConfig({ environment: "production" })) });

export const TIMING = Object.freeze({ requestMs: 300, rpcMs: 300, startWindowMs: 60, commitBudgetMs: 200, lookupMs: 150,
  releaseMs: 150 });

/** The section 4.55.4 envelope as SQL returns it (JSON-compatible). */
export function envelope(state = "sent", extra = {}) {
  const mode = extra.mode ?? "test";
  const classification = extra.classification ?? (mode === "test" ? `test_${state}` : {
    sent: "in_progress", unknown: "in_progress", released: "in_progress", approved: "approved_unrecorded",
    declined: "declined" }[state]);
  const out = { ok: true, attempt_id: ATTEMPT, state, classification, recorded: false, amount_minor: 1234,
    currency_code: "ILS", server_ts: TS, ...extra };
  delete out.mode;
  return out;
}

/** The adapter-only facts of a claim / adapter read. */
export function adapterFacts({ mode = "test", fresh = true, ...extra } = {}) {
  return { attempt_row_id: ROW, organization_id: ORG, restaurant_id: REST, device_id: DEVICE, local_operation_id: ATTEMPT,
    mode, terminal_ref: mode === "test" ? "pad-test" : "pad-live", credential_ref: mode === "test" ? "cred-test" : "cred-live",
    start_deadline_at: "2026-10-27T10:02:00.123456+00:00",
    ...(fresh ? { provider_key_format_version: "alpha16-l24-v1", provider_query_key: QUERY_KEY,
      provider_duplicate_key: DUPLICATE_KEY } : {}),
    ...extra };
}

export const freshClaim = (mode = "test", extra = {}) => ({ ...envelope("sent", { mode }), ...adapterFacts({ mode }),
  claim_created: true, replayed: false, ...extra });
export const replayClaim = (state = "sent", mode = "test", extra = {}) => ({ ...envelope(state, { mode }),
  ...adapterFacts({ mode, fresh: false }), claim_created: false, replayed: true, ...extra });
export const adapterRead = (state = "sent", mode = "test", extra = {}) => ({ ...envelope(state, { mode }),
  ...adapterFacts({ mode }), start_deadline_passed: false, auto_poll_count: 0, last_lookup_at: null,
  release_requested_at: null, ...extra });

export function contextOk(extra = {}) {
  return { ok: true, caller_auth_user_id: CALLER, organization_id: ORG, restaurant_id: REST, branch_id: BRANCH,
    device_id: DEVICE, role: "cashier", employee_profile_id: EMPLOYEE, membership_id: MEMBERSHIP, order: null,
    attempt: null, terminal: { lifecycle: "enabled", mode: "test" }, card_terminal_enabled: true, server_ts: TS, ...extra };
}

/** The context proof's attempt projection: the envelope without ok / server_ts, plus mode and own_device. */
export function contextAttempt(state = "sent", mode = "test", extra = {}) {
  const value = { ...envelope(state, { mode }), mode, own_device: true, ...extra };
  delete value.ok;
  delete value.server_ts;
  return value;
}

const jsonAnswer = (value, status = 200) => new Response(typeof value === "string" ? value : JSON.stringify(value),
  { status, headers: { "content-type": "application/json" } });

/** Abortable delayed answer, like a real fetch. */
export function later(ms, make) {
  return (init) => new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      try { resolve(make()); } catch (error) { reject(error); }
    }, ms);
    init.signal?.addEventListener("abort", () => { clearTimeout(timer); reject(new DOMException("aborted", "AbortError")); },
      { once: true });
  });
}

/** An answer that never arrives (until the caller aborts it): a worker that dies mid-commit. */
export const never = (init) => new Promise((_, reject) => {
  init.signal?.addEventListener("abort", () => reject(new DOMException("aborted", "AbortError")), { once: true });
});

/**
 * A scripted world. `rpc[name]` and `provider[op]` are a value, a Response, a function of
 * (parsedBody, init, callIndex) or an array consumed in order.
 */
export function world({ env = {}, rpc = {}, provider = {}, profile = SYNTHETIC_PROFILE, timing = TIMING } = {}) {
  const calls = { rpc: [], provider: [], other: [] };
  const tasks = [];
  const reads = [];
  const config = { SUPABASE_URL: BASE, SUPABASE_ANON_KEY: ANON, SUPABASE_SERVICE_ROLE_KEY: SERVICE,
    POS_CARD_PAYMENTS_ENABLED: "true", POS_CARD_PROVIDER_CONFIG: JSON.stringify(providerConfig()), ...env };
  const pick = (script, args) => {
    let entry = script;
    if (Array.isArray(entry)) entry = entry.length > 1 ? entry.shift() : entry[0];
    return typeof entry === "function" ? entry(...args) : entry;
  };
  const parse = (text) => { try { return JSON.parse(text); } catch { return null; } };
  // The provider operation a URL addresses: a synthetic /synthetic/<op> route, or one of the world profile's own routes
  // (a vendor-shaped candidate such as lib/provider/zcredit_profile.mjs) under the same synthetic base.
  const record = (value) => value !== null && typeof value === "object";
  const routes = record(profile) && record(profile.routes) ? profile.routes : {};
  const operationOf = (url) => {
    if (url.startsWith(`${PROVIDER_BASE}/synthetic/`)) return url.slice(`${PROVIDER_BASE}/synthetic/`.length);
    return Object.keys(routes).find((op) => typeof routes[op] === "string" && url === `${PROVIDER_BASE}${routes[op]}`) ?? null;
  };
  const fetchImpl = async (url, init) => {
    if (url.startsWith(`${BASE}/rest/v1/rpc/`)) {
      const name = url.slice(`${BASE}/rest/v1/rpc/`.length);
      const call = { name, raw: init.body, body: parse(init.body), headers: init.headers, init };
      calls.rpc.push(call);
      if (!Object.hasOwn(rpc, name)) { stray.push(`unscripted rpc ${name}`); throw new Error(`unscripted rpc ${name}`); }
      const result = await pick(rpc[name], [call.body, init, calls.rpc.filter((c) => c.name === name).length]);
      return result instanceof Response ? result : jsonAnswer(result);
    }
    const op = operationOf(url);
    if (op !== null) {
      calls.provider.push({ op, url, raw: init.body, body: parse(init.body), headers: init.headers, init });
      if (!Object.hasOwn(provider, op)) { stray.push(`unscripted provider ${op}`); throw new Error(`unscripted provider ${op}`); }
      const result = await pick(provider[op], [init, calls.provider.filter((c) => c.op === op).length]);
      return result instanceof Response ? result : jsonAnswer(result);
    }
    calls.other.push(url);
    stray.push(`unexpected host ${url}`);
    throw new Error(`unexpected host ${url}`);
  };
  const handler = createHandler({ getEnv: (name) => { reads.push(name); return config[name]; }, fetchImpl,
    waitUntil: (task) => { tasks.push(task); allTasks.push(task); }, providerProfile: profile, timing });
  const run = async (input, options = {}) => {
    const headers = { "content-type": "application/json", authorization: `Bearer ${options.jwt ?? JWT}`, ...options.headers };
    for (const key of Object.keys(headers)) if (headers[key] === null) delete headers[key];
    const response = await handler(new Request(options.url ?? `${BASE}/functions/v1/pos-card-charge`, {
      method: options.method ?? "POST", headers,
      ...((options.method ?? "POST") === "POST" ? { body: typeof input === "string" ? input : JSON.stringify(input) } : {}),
    }));
    const text = await response.text();
    return { status: response.status, text, body: text ? JSON.parse(text) : null, headers: response.headers };
  };
  const settle = () => Promise.all(tasks);
  const rpcNames = () => calls.rpc.map((call) => call.name);
  return { calls, tasks, reads, config, handler, run, settle, rpcNames, fetchImpl };
}

/** Every provider request carries exactly the two JSON headers and no platform secret or caller JWT. */
export function assertCleanProviderRequests(assert, w) {
  for (const call of w.calls.provider) {
    assert.deepEqual(Object.keys(call.headers).sort(), ["Accept", "Content-Type"]);
    assert.equal(call.headers["Content-Type"], "application/json; charset=utf-8");
    assert.equal(call.headers.Accept, "application/json");
    const everything = `${JSON.stringify(call.headers)}${call.raw}${call.url}`;
    for (const secret of [SERVICE, ANON, JWT, TOKEN]) assert.ok(!everything.includes(secret), "no platform secret or JWT reaches the provider");
  }
}

const common = (action, extra = {}) => ({ action, pin_session_id: PIN, device_id: DEVICE, device_session_token: TOKEN,
  attempt_id: ATTEMPT, ...extra });

/** Raw JSON request text: amount_minor and expected_revision stay integer tokens. */
export const startTest = (extra = {}) => common("start", { mode: "test", amount_minor: 1234, currency_code: "ILS", ...extra });
export const startLive = (extra = {}) => common("start", { mode: "live", amount_minor: 1234, currency_code: "ILS",
  order_id: ORDER, expected_revision: 7, ...extra });
export const statusInput = (extra = {}) => common("status", extra);
export const releaseInput = (extra = {}) => common("release", extra);
export const freeInput = (extra = {}) => common("free_order", { reason: "Provider report shows no charge",
  confirmation_source: "provider_report", confirmation_reference: "RPT-2026-10-27/syn", ...extra });

/** A raw JSON number token for a provider reply, written exactly as given (12.30 keeps its zero; DECISION D-064). */
export const numberToken = (text) => JSON.rawJSON(text);

/** A provider reply with unsafe extras that must never be read (card number, token, receipt, message). */
export function providerReply(fields = {}) {
  const reply = { SynError: false, SynReturn: 0, SynApproval: "A1", SynPhone: false, SynReference: "SYN-REF-1",
    SynApprovalNumber: "APPR1", SynVoucher: "VCH1", SynLast4: "4242", SynBrand: "BR1", SynEntry: "CHIP",
    SynMethod: "CARD", SynSavedAt: "2026-10-27T10:00:05Z",
    SynCardNumber: "SYNTHETIC-CARD-FIELD", SynToken: "SYNTHETIC-TOKEN", SynReceipt: "SYNTHETIC RECEIPT TEXT",
    SynMessage: "SYNTHETIC VENDOR MESSAGE", ...fields };
  for (const key of Object.keys(fields)) if (fields[key] === undefined) delete reply[key];
  return reply;
}
