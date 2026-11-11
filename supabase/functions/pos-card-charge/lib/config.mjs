// BIZBOT-PAYMENTS-ZCREDIT-PILOT-001E: environment NAMES and the shape-validated provider
// configuration (API_CONTRACT section 4.55.9; DEPLOYMENT section 18.4). Values are read through
// one allowlisted accessor; no value is ever logged, returned or passed to SQL - SQL receives only
// the reference projections (terminal_ref -> credential_ref, credential_ref -> mode / scope /
// restaurant_id). The service-role key is NOT readable through this accessor: its name and its
// single-name reader live in ledger.mjs only.
import { isObject, parseJson } from "./json.mjs";
import { KEY_FORMATS, REFERENCE, UUID } from "./constants.mjs";
import { safeTextFailure } from "./text_policy.mjs";

export const ENV_NAMES = Object.freeze({
  url: "SUPABASE_URL",
  anonKey: "SUPABASE_ANON_KEY",
  enabled: "POS_CARD_PAYMENTS_ENABLED",
  provider: "POS_CARD_PROVIDER_CONFIG",
});

/** Wrap the platform accessor so only these four names can be read. */
export function allowlistedEnv(getEnv) {
  const allowed = new Set(Object.values(ENV_NAMES));
  return (name) => {
    if (!allowed.has(name)) throw new Error("environment name outside the allowlist");
    const value = getEnv(name);
    return typeof value === "string" ? value : undefined;
  };
}

/** The platform project origin (https, or a local development host), else null. */
export function platformBase(env) {
  let url;
  try { url = new URL(env(ENV_NAMES.url)); } catch { return null; }
  const local = url.protocol === "http:" && (["localhost", "127.0.0.1", "[::1]"].includes(url.hostname)
    || (url.hostname === "kong" && url.port === "8000"));
  if ((url.protocol !== "https:" && !local) || url.username || url.password || url.search || url.hash
    || !["", "/"].includes(url.pathname)) return null;
  return url.origin;
}

/** A platform key: non-empty, no whitespace, bounded. */
export function platformKey(value) {
  return typeof value === "string" && /^[\x21-\x7e]{20,4096}$/.test(value) ? value : null;
}

/** The master flag: exactly the text 'true'. */
export function masterFlagOn(env) {
  return env(ENV_NAMES.enabled) === "true";
}

const exactKeys = (value, required, optional = []) => isObject(value)
  && required.every((key) => Object.hasOwn(value, key))
  && Object.keys(value).every((key) => required.includes(key) || optional.includes(key));
const opaque = (value, max) => typeof value === "string" && value.length >= 1 && value.length <= max
  && /^[\x21-\x7e]+$/.test(value);
const reference = (value, field) => typeof value === "string" && REFERENCE.test(value)
  && safeTextFailure(value, field) === null;

function baseUrl(value) {
  if (typeof value !== "string" || value.length > 512) return null;
  let url;
  try { url = new URL(value); } catch { return null; }
  if (url.protocol !== "https:" || url.username || url.password || url.search || url.hash
    || value.includes("#") || value.includes("?")
    || !/^(?:\/[A-Za-z0-9._~-]+)*\/?$/.test(url.pathname)) return null;
  return `${url.origin}${url.pathname.replace(/\/$/, "")}`;
}

function credentialRecord(value) {
  if (!exactKeys(value, ["mode", "scope", "secret"], ["restaurant_id"])) return null;
  const { mode, scope, secret } = value;
  if (mode === "test") {
    if (scope !== "development" || (Object.hasOwn(value, "restaurant_id") && value.restaurant_id !== null)) return null;
  } else if (mode === "live") {
    if (scope !== "merchant" || typeof value.restaurant_id !== "string" || !UUID.test(value.restaurant_id)) return null;
  } else {
    return null;
  }
  if (!isObject(secret)) return null;
  const names = Object.keys(secret);
  if (names.length < 1 || names.length > 16 || !names.every((name) => /^[a-z][a-z0-9_]{0,31}$/.test(name)
    && opaque(secret[name], 256))) return null;
  return Object.freeze({ mode, scope, restaurantId: mode === "live" ? value.restaurant_id : null,
    secret: Object.freeze(Object.assign(Object.create(null), secret)) });
}

/**
 * Parse POS_CARD_PROVIDER_CONFIG. Exactly: environment, base_url, key_format, credentials,
 * terminals. Returns the frozen configuration or null (missing or failing shape validation).
 */
export function providerConfiguration(env) {
  const raw = env(ENV_NAMES.provider);
  if (typeof raw !== "string" || raw.length === 0 || raw.length > 48 * 1024) return null;
  let value;
  try { value = parseJson(raw); } catch { return null; }
  if (!exactKeys(value, ["environment", "base_url", "key_format", "credentials", "terminals"])) return null;
  if (!["test", "production"].includes(value.environment) || !KEY_FORMATS.includes(value.key_format)) return null;
  const base = baseUrl(value.base_url);
  if (!base || !isObject(value.credentials) || !isObject(value.terminals)) return null;
  // Null-prototype maps: a reference spelled like an Object.prototype member stays an own key.
  const credentials = Object.create(null);
  const credentialRefs = Object.keys(value.credentials);
  if (credentialRefs.length < 1 || credentialRefs.length > 32) return null;
  for (const ref of credentialRefs) {
    const record = credentialRecord(value.credentials[ref]);
    if (!reference(ref, "credential_ref") || !record) return null;
    credentials[ref] = record;
  }
  const terminals = Object.create(null);
  const terminalRefs = Object.keys(value.terminals);
  if (terminalRefs.length < 1 || terminalRefs.length > 32) return null;
  for (const ref of terminalRefs) {
    const record = value.terminals[ref];
    if (!reference(ref, "terminal_ref") || !exactKeys(record, ["credential_ref", "pinpad_id"])
      || !reference(record.credential_ref, "credential_ref") || !opaque(record.pinpad_id, 64)) return null;
    terminals[ref] = Object.freeze({ credentialRef: record.credential_ref, pinpadId: record.pinpad_id });
  }
  return Object.freeze({ environment: value.environment, baseUrl: base, keyFormat: value.key_format,
    credentials: Object.freeze(credentials), terminals: Object.freeze(terminals) });
}

/** The SQL projections of section 4.55.4 step (3): references, tokens and ids only. */
export function sqlMaps(config) {
  if (!config) return { environment: null, terminals: {}, credentials: {} };
  const terminals = Object.create(null);
  for (const [ref, record] of Object.entries(config.terminals)) terminals[ref] = record.credentialRef;
  const credentials = Object.create(null);
  for (const [ref, record] of Object.entries(config.credentials)) {
    credentials[ref] = record.mode === "live"
      ? { mode: record.mode, scope: record.scope, restaurant_id: record.restaurantId }
      : { mode: record.mode, scope: record.scope };
  }
  return { environment: config.environment, terminals, credentials };
}
