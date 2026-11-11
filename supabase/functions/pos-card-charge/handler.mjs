// BIZBOT-PAYMENTS-ZCREDIT-PILOT-001E: the pos-card-charge Edge Function (API_CONTRACT section
// 4.55; execution packet docs/BIZBOT_PAYMENTS_ZCREDIT_PILOT_001E_EXECUTION.md).
//
// Initiate and poll: `start` claims the attempt and sends ONE provider commit only for the request
// whose claim inserted the fresh row (claim_created = true), answering within a short window -
// never for the whole terminal interaction; `status` performs one bounded lookup by the stored
// key; `release` is advisory; `free_order` is the manager's evidence-bound free. Every action
// proves the caller first through the caller-scoped read-only context proof; only then does the
// ledger module open the service-role client, bound to that proof's caller. No automatic retry,
// no logging, nothing about the provider reaches the POS beyond the closed envelope.
import { allowlistedEnv, ENV_NAMES, masterFlagOn, platformBase, platformKey, providerConfiguration, sqlMaps }
  from "./lib/config.mjs";
import { openLedger, serviceKeySource } from "./lib/ledger.mjs";
import { proveContext } from "./lib/caller.mjs";
import { parseRequest } from "./lib/request.mjs";
import { decodeJson, delay, jsonResponse, readBounded } from "./lib/http.mjs";
import { projectEnvelope, projectRefusal, statusOf } from "./lib/envelope.mjs";
import { AUTO_POLL_CAP, KEY_FORMATS, KEY_LENGTH, LIMITS, MANAGER_ROLES, POLL_MIN_INTERVAL_MS, REFERENCE, TIMING, UUID,
  UUID_V4 } from "./lib/constants.mjs";
import { createProvider, NotSendable, secretNames, validateProfile } from "./lib/provider/engine.mjs";
import { JsonNumber, integerText } from "./lib/json.mjs";
import { minorFromToken } from "./lib/money.mjs";
import { timestampMs } from "./lib/time.mjs";

const PATHS = new Set(["/pos-card-charge", "/functions/v1/pos-card-charge"]);
const BEARER = /^Bearer [A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/;
const MEDIA = /^application\/json(?:\s*;\s*charset\s*=\s*(?:utf-8|"utf-8"))?\s*$/i;
const LOOKUP_STATES = ["sent", "unknown", "released"];
const RELEASE_STATES = ["sent", "unknown"];
const UNAVAILABLE = Object.freeze({ ok: false, error: "unavailable" });

const refusal = (error, extra = {}) => ({ ok: false, error, ...extra });
const reply = (body, status) => jsonResponse(body, status ?? statusOf(body));

/**
 * The adapter-only facts of a claim or adapter read: the finish scope and the frozen references.
 * Whether the configuration can still serve those references is checked only where a provider call
 * follows (SQL first, then servable()), so an approved, declined or resolved attempt never depends
 * on the configuration.
 */
function adapterScope(answer, input) {
  const amount = answer.amount_minor instanceof JsonNumber ? minorFromToken(answer.amount_minor) : null;
  if (typeof answer.attempt_row_id !== "string" || !UUID.test(answer.attempt_row_id)
    || typeof answer.organization_id !== "string" || !UUID.test(answer.organization_id)
    || typeof answer.restaurant_id !== "string" || !UUID.test(answer.restaurant_id)
    || typeof answer.device_id !== "string" || !UUID.test(answer.device_id)
    || answer.local_operation_id !== input.attemptId || !UUID_V4.test(answer.local_operation_id)
    || !["test", "live"].includes(answer.mode) || amount === null
    || typeof answer.currency_code !== "string" || !/^[A-Z]{3}$/.test(answer.currency_code)
    || typeof answer.terminal_ref !== "string" || !REFERENCE.test(answer.terminal_ref)
    || typeof answer.credential_ref !== "string" || !REFERENCE.test(answer.credential_ref)) return null;
  return Object.freeze({ attemptRowId: answer.attempt_row_id, organizationId: answer.organization_id,
    restaurantId: answer.restaurant_id, deviceId: answer.device_id, localOperationId: answer.local_operation_id,
    mode: answer.mode, amountToken: answer.amount_minor, amountMinor: amount, currencyCode: answer.currency_code,
    terminalRef: answer.terminal_ref, credentialRef: answer.credential_ref });
}

/**
 * Defence in depth on the service read (RISK R-003): the row belongs to the proof's organization and
 * restaurant, and a cashier only ever reaches the originating till's attempt (a manager+ may act on
 * another device of the same branch, which the SQL resolution scopes).
 */
function sameScope(scope, proven, input) {
  return scope.organizationId === proven.organizationId && scope.restaurantId === proven.restaurantId
    && (MANAGER_ROLES.includes(proven.role) || scope.deviceId === input.deviceId);
}

/** The stored outbound keys exactly as SQL returned them (the adapter never derives a key). */
function storedKeys(answer, keyFormat) {
  const version = answer.provider_key_format_version;
  if (!KEY_FORMATS.includes(version) || (keyFormat !== null && version !== keyFormat)) return null;
  const shape = new RegExp(`^[a-p]{${KEY_LENGTH[version]}}$`);
  const query = answer.provider_query_key;
  const duplicate = answer.provider_duplicate_key;
  if (typeof query !== "string" || typeof duplicate !== "string" || !shape.test(query) || !shape.test(duplicate)
    || query === duplicate) return null;
  return Object.freeze({ query, duplicate });
}

/** Before any claim: every credential record can feed the profile (the device's mapping is not yet known). */
function compatible(config, profile) {
  const names = [...secretNames(profile)];
  return Object.values(config.credentials).every((record) => names.every((name) => Object.hasOwn(record.secret, name)));
}

/**
 * Before a provider call for an existing attempt: the configuration still holds the attempt's OWN
 * frozen terminal and credential records, consistently, in the environment of its mode, and that
 * credential can feed the profile. Other records never matter (section 4.55.5).
 */
function servable(config, scope, profile) {
  if (!Object.hasOwn(config.terminals, scope.terminalRef) || !Object.hasOwn(config.credentials, scope.credentialRef)) return false;
  const credential = config.credentials[scope.credentialRef];
  return config.terminals[scope.terminalRef].credentialRef === scope.credentialRef
    && credential.mode === scope.mode && config.environment === (scope.mode === "live" ? "production" : "test")
    && [...secretNames(profile)].every((name) => Object.hasOwn(credential.secret, name));
}

/**
 * Inside the minimum interval since a stamp (database clock: the answer's server_ts); null when the
 * stamp key is absent or unreadable (fail closed). Never stamped (SQL null) is outside it, and so is a
 * stamp ahead of the clock: a clock stepped back never suppresses a call.
 */
function withinInterval(stamp, serverTs) {
  if (stamp === null) return false;
  const last = timestampMs(stamp);
  const now = timestampMs(serverTs);
  if (last === null || now === null) return null;
  return now >= last && now - last < POLL_MIN_INTERVAL_MS;
}

/**
 * @param {{ getEnv: (name: string) => string | undefined, fetchImpl?: typeof fetch,
 *   waitUntil?: (task: Promise<unknown>) => void, providerProfile?: object | null, timing?: typeof TIMING }} options
 */
export function createHandler({ getEnv, fetchImpl = globalThis.fetch, waitUntil = () => {}, providerProfile = null,
  timing = TIMING } = {}) {
  // The only two uses of the platform accessor: four public names here, the service key in the ledger.
  const env = allowlistedEnv(getEnv);
  const keySource = serviceKeySource(getEnv);
  let provider = null;
  if (providerProfile !== null) {
    try {
      const profile = validateProfile(providerProfile);
      provider = { profile, transport: createProvider({ profile, fetchImpl, maxBytes: LIMITS.providerReplyBytes }) };
    } catch {
      provider = null; // an invalid profile is no profile: fail closed
    }
  }

  const prove = (session, input, attemptId) => proveContext({ request: session.request, base: session.base,
    anonKey: session.anonKey, authorization: session.authorization, fetchImpl, deadlineMs: timing.rpcMs,
    maxBytes: LIMITS.rpcAnswerBytes, args: { pinSessionId: input.pinSessionId, deviceId: input.deviceId,
      deviceSessionToken: input.deviceSessionToken, orderId: null, attemptId } });
  const ledgerFor = (session, proven) => openLedger({ keySource, fetchImpl, base: session.base, deadlineMs: timing.rpcMs,
    maxBytes: LIMITS.rpcAnswerBytes, proven, request: session.request });
  const projected = (answer) => (answer.ok === false ? projectRefusal(answer) : projectEnvelope(answer)) ?? UNAVAILABLE;
  const providerContext = (scope, config, extra) => ({ config, terminalRef: scope.terminalRef,
    credentialRef: scope.credentialRef, mode: scope.mode, ...extra });

  // The one commit of a fresh claim, then its provider fact through the scope-bound finish. Runs on
  // after the start answer through waitUntil - an optimization bounded by the worker's remaining
  // lifetime, not a durable queue: if the worker ends first the attempt stays sent (then unknown)
  // and is recovered only by status lookups under the same identity.
  async function commitAndFinish(ledger, scope, keys, config) {
    let result;
    try {
      result = await provider.transport.commit(providerContext(scope, config, { statusKey: keys.query,
        duplicateKey: keys.duplicate, amountMinor: scope.amountMinor, currencyCode: scope.currencyCode }),
      { deadlineMs: timing.commitBudgetMs });
    } catch (error) {
      if (error instanceof NotSendable) return null; // nothing was sent: no provider fact exists
      result = { outcome: "unknown", fields: {} };
    }
    try {
      return await ledger.finish(scope, { source: "commit", outcome: result.outcome, fields: result.fields, pollSource: null });
    } catch {
      return null; // the fact is recovered by a later status lookup
    }
  }

  async function start(session, input) {
    // (1) before any database read (API_CONTRACT section 4.55.4).
    if (!masterFlagOn(env)) return refusal("card_payments_disabled");
    const config = providerConfiguration(env);
    if (!config || !provider || !compatible(config, provider.profile)
      || !Object.hasOwn(provider.profile.codes.currencyRequest, input.currencyCode)) return refusal("provider_unavailable");
    // (2) the caller-scoped context proof.
    const proof = await prove(session, input, null);
    if (proof.kind === "refused") return refusal(proof.error);
    if (proof.kind !== "proven") return UNAVAILABLE;
    // (3)-(4) the service-only claim, bound to the same request's proven caller.
    const ledger = ledgerFor(session, proof.proven);
    if (!ledger) return UNAVAILABLE;
    let claim;
    try {
      claim = await ledger.claim(input, { mode: input.mode, amountToken: input.amountToken,
        currencyCode: input.currencyCode, orderId: input.orderId, expectedRevision: input.expectedRevision,
        maps: sqlMaps(config), keyFormat: config.keyFormat });
    } catch {
      return UNAVAILABLE; // the claim's outcome is unknown: no provider call; status recovers it
    }
    if (claim.ok === false) return projected(claim);
    const envelope = projectEnvelope(claim);
    if (!envelope) return UNAVAILABLE;
    // An idempotent replay or a concurrent loser answers the stored state: zero provider requests.
    if (claim.claim_created !== true || claim.replayed !== false) return envelope;
    const scope = adapterScope(claim, input);
    const keys = storedKeys(claim, config.keyFormat);
    if (!scope || !keys || scope.mode !== input.mode || scope.amountMinor !== input.amountMinor
      || scope.currencyCode !== input.currencyCode || scope.deviceId !== input.deviceId
      || scope.organizationId !== proof.proven.organizationId || scope.restaurantId !== proof.proven.restaurantId
      || claim.state !== "sent" || !servable(config, scope, provider.profile)) return envelope;
    // (5) the one provider commit, answered early when it completes inside the window.
    const task = commitAndFinish(ledger, scope, keys, config);
    try { waitUntil(task); } catch { /* the task still runs within this request */ }
    const stop = new AbortController();
    const early = await Promise.race([task, delay(timing.startWindowMs, stop.signal).then(() => null)]);
    stop.abort();
    return (early && projectEnvelope(early)) ?? envelope;
  }

  async function status(session, input) {
    const config = providerConfiguration(env); // absent or invalid: empty maps (section 4.55.5)
    const proof = await prove(session, input, input.attemptId);
    if (proof.kind === "refused") return refusal(proof.error);
    if (proof.kind !== "proven") return UNAVAILABLE;
    if (proof.proven.attempt === null) return refusal("attempt_not_found");
    const ledger = ledgerFor(session, proof.proven);
    if (!ledger) return UNAVAILABLE;
    let read;
    try { read = await ledger.adapterRead(input, sqlMaps(config)); } catch { return UNAVAILABLE; }
    if (read.ok === false) return projected(read);
    const envelope = projectEnvelope(read);
    const scope = adapterScope(read, input);
    if (!envelope || !scope || !sameScope(scope, proof.proven, input)) return UNAVAILABLE;
    if (read.resolution !== undefined) return envelope; // final: no provider call
    if (read.state === "approved") {
      if (!input.recordingRefused) return envelope;
      try { return projected(await ledger.markRecordingResult(input, input.refusalCode)); } catch { return UNAVAILABLE; }
    }
    if (!LOOKUP_STATES.includes(read.state)) return envelope;
    const position = { attempt_id: envelope.attempt_id, attempt_state: envelope.state };
    if (input.source === "auto" && !MANAGER_ROLES.includes(proof.proven.role)) {
      const polls = integerText(read.auto_poll_count, 0, 2147483647);
      if (polls === null) return UNAVAILABLE;
      if (BigInt(polls) >= BigInt(AUTO_POLL_CAP)) return refusal("poll_limit", position);
    }
    // The cadence applies to every source and role: inside it the stored envelope, no provider call, no write.
    const recent = withinInterval(read.last_lookup_at, read.server_ts);
    if (recent === null) return UNAVAILABLE;
    if (recent) return envelope;
    if (!provider || !config || !servable(config, scope, provider.profile)) return refusal("provider_unavailable", position);
    const keys = storedKeys(read, null);
    if (!keys) return UNAVAILABLE;
    let result;
    try {
      result = await provider.transport.lookup(providerContext(scope, config, { statusKey: keys.query }),
        { deadlineMs: timing.lookupMs });
    } catch (error) {
      if (error instanceof NotSendable) return refusal("provider_unavailable", position);
      result = { outcome: "failed", fields: {} };
    }
    try {
      const finished = await ledger.finish(scope, { source: "lookup", outcome: result.outcome, fields: result.fields,
        pollSource: input.source });
      return finished.ok === false ? UNAVAILABLE : (projectEnvelope(finished) ?? UNAVAILABLE);
    } catch {
      return UNAVAILABLE;
    }
  }

  async function release(session, input) {
    const config = providerConfiguration(env);
    const proof = await prove(session, input, input.attemptId);
    if (proof.kind === "refused") return refusal(proof.error);
    if (proof.kind !== "proven") return UNAVAILABLE;
    const attempt = proof.proven.attempt;
    if (attempt === null) return refusal("attempt_not_found");
    if (!RELEASE_STATES.includes(attempt.state) || attempt.resolution !== undefined) {
      // Not releasable: the current envelope - no adapter read, no write, no provider call.
      return projectEnvelope({ ...attempt, ok: true, server_ts: proof.proven.serverTs }) ?? UNAVAILABLE;
    }
    const ledger = ledgerFor(session, proof.proven);
    if (!ledger) return UNAVAILABLE;
    let read;
    try { read = await ledger.adapterRead(input, sqlMaps(config)); } catch { return UNAVAILABLE; }
    if (read.ok === false) return projected(read);
    const envelope = projectEnvelope(read);
    const scope = adapterScope(read, input);
    if (!envelope || !scope || !sameScope(scope, proof.proven, input)) return UNAVAILABLE;
    if (read.resolution !== undefined || !RELEASE_STATES.includes(read.state)) return envelope;
    const position = { attempt_id: envelope.attempt_id, attempt_state: envelope.state };
    // A release requested within the minimum interval answers the stored envelope - no mark, no provider
    // call. It is not a confirmation: only state 'released' confirms a release, and a retry after the
    // interval marks again and calls the provider (section 4.55.6 sets no release rate; a recorded addition).
    const recent = withinInterval(read.release_requested_at, read.server_ts);
    if (recent === null) return UNAVAILABLE;
    if (recent) return envelope;
    if (!provider || !provider.transport.supportsRelease || !config || !servable(config, scope, provider.profile)) {
      return refusal("provider_unavailable", position);
    }
    let marked;
    try { marked = await ledger.markReleaseRequested(input); } catch { return UNAVAILABLE; }
    if (marked.ok === false) return projected(marked);
    if (!RELEASE_STATES.includes(marked.state) || marked.resolution !== undefined) return projected(marked);
    let result;
    try {
      result = await provider.transport.release(providerContext(scope, config, {}), { deadlineMs: timing.releaseMs });
    } catch (error) {
      if (error instanceof NotSendable) return refusal("provider_unavailable", position); // nothing was sent
      result = { outcome: "release_failed", fields: {} };
    }
    try {
      // The release result carries no provider value, only its dropped-field evidence (DECISION D-062).
      const finished = await ledger.finish(scope, { source: "release", outcome: result.outcome, fields: result.fields,
        pollSource: null });
      return finished.ok === false ? UNAVAILABLE : (projectEnvelope(finished) ?? UNAVAILABLE);
    } catch {
      return UNAVAILABLE;
    }
  }

  async function freeOrder(session, input) {
    const proof = await prove(session, input, null); // role first: no attempt is looked up here
    if (proof.kind === "refused") return refusal(proof.error);
    if (proof.kind !== "proven") return UNAVAILABLE;
    if (!MANAGER_ROLES.includes(proof.proven.role)) return refusal("permission_denied");
    const ledger = ledgerFor(session, proof.proven);
    if (!ledger) return UNAVAILABLE;
    try {
      return projected(await ledger.freeOrder(input, { reason: input.reason,
        confirmationSource: input.confirmationSource, confirmationReference: input.confirmationReference }));
    } catch {
      return UNAVAILABLE;
    }
  }

  const ACTIONS = { start, status, release, free_order: freeOrder };

  return async function handler(request) {
    try {
      if (request.headers.has("origin")) return reply(refusal("origin_not_allowed"), 403); // native POS only
      const url = new URL(request.url);
      if (url.search || !PATHS.has(url.pathname)) return reply(refusal("not_found"), 404);
      if (request.method !== "POST") return reply(refusal("method_not_allowed"), 405);
      const authorization = request.headers.get("authorization");
      if (typeof authorization !== "string" || authorization.length > 8192 || !BEARER.test(authorization)) {
        return reply(refusal("invalid_session"), 401);
      }
      const encoding = request.headers.get("content-encoding");
      if (!MEDIA.test(request.headers.get("content-type") ?? "") || (encoding !== null && encoding.toLowerCase() !== "identity")) {
        return reply(refusal("invalid_request"), 400);
      }
      let input = null;
      try {
        input = parseRequest(decodeJson(await readBounded(request, LIMITS.requestBytes, timing.requestMs)));
      } catch {
        input = null;
      }
      if (!input) return reply(refusal("invalid_request"), 400);
      const base = platformBase(env);
      const anonKey = platformKey(env(ENV_NAMES.anonKey));
      if (!base || !anonKey) return reply(UNAVAILABLE, 503);
      // A fresh scope per request: a proof, and so a binding, can never cross requests.
      const session = Object.freeze({ request: Object.freeze({}), base, anonKey, authorization });
      return reply(await ACTIONS[input.action](session, input));
    } catch {
      return reply(UNAVAILABLE, 503); // no exception, body, credential or provider text is logged or returned
    }
  };
}
