import { hashStatusToken } from "./validation.mjs";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const UUID_V4 = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const DIGEST = /^[0-9a-f]{64}$/;
const BEARER = /^Bearer ([A-Za-z0-9_-]{42}[AEIMQUYcgkosw048])$/;
const KEYS = ["slug", "organization_id", "restaurant_id", "branch_id", "request_id", "not_before", "expires_at", "authorization_sha256", "status_token_sha256", "order_sha256"];
const MAX_WINDOW_MS = 15 * 60 * 1000;

function instant(value) {
  if (typeof value !== "string") return NaN;
  const ms = Date.parse(value);
  return Number.isFinite(ms) && new Date(ms).toISOString() === value ? ms : NaN;
}

// Fixed-length digest comparison without a data-dependent early exit.
function sameDigest(actual, expected) {
  let difference = 0;
  for (let index = 0; index < 64; index++) difference |= actual.charCodeAt(index) ^ expected.charCodeAt(index);
  return difference === 0;
}

/** Server-only permit. Nothing from this object is projected into public responses. */
export async function authorizeTestSubmission({ input, request, getEnv, cryptoImpl, now }) {
  try {
    if (input.action !== "submit" || getEnv("WEB_ORDERS_ENABLED") === "true" || getEnv("WEB_ORDERS_TEST_ENABLED") !== "true") return null;
    const raw = getEnv("WEB_ORDERS_TEST_PERMIT");
    if (typeof raw !== "string" || raw.length > 4096) return null;
    const permit = JSON.parse(raw);
    if (!permit || typeof permit !== "object" || Array.isArray(permit) || Object.keys(permit).length !== KEYS.length || KEYS.some((key) => !Object.hasOwn(permit, key))) return null;
    if (permit.slug !== "mapsburger" || input.slug !== permit.slug || !UUID_V4.test(permit.request_id) || input.request_id !== permit.request_id) return null;
    if ([permit.organization_id, permit.restaurant_id, permit.branch_id].some((id) => typeof id !== "string" || !UUID.test(id) || id === "00000000-0000-0000-0000-000000000000")) return null;
    if ([permit.authorization_sha256, permit.status_token_sha256, permit.order_sha256].some((digest) => typeof digest !== "string" || !DIGEST.test(digest))) return null;
    if (permit.authorization_sha256 === permit.status_token_sha256) return null;
    const notBefore = instant(permit.not_before);
    const expiresAt = instant(permit.expires_at);
    const started = now();
    if (!Number.isFinite(started) || !Number.isFinite(notBefore) || !Number.isFinite(expiresAt) || expiresAt <= notBefore || expiresAt - notBefore > MAX_WINDOW_MS || started < notBefore || started >= expiresAt) return null;
    const bearer = BEARER.exec(request.headers.get("authorization") ?? "");
    if (!bearer) return null;
    const [authorizationHash, statusHash, orderHash] = await Promise.all([
      hashStatusToken(bearer[1], cryptoImpl),
      hashStatusToken(input.status_token, cryptoImpl),
      hashStatusToken(JSON.stringify(input.order), cryptoImpl),
    ]);
    if (!sameDigest(authorizationHash, permit.authorization_sha256) || !sameDigest(statusHash, permit.status_token_sha256) || !sameDigest(orderHash, permit.order_sha256)) return null;
    const finished = now();
    if (!Number.isFinite(finished) || finished < notBefore || finished >= expiresAt) return null;
    return {
      organizationId: permit.organization_id, restaurantId: permit.restaurant_id, branchId: permit.branch_id,
      requestId: permit.request_id, notBefore: permit.not_before, expiresAt: permit.expires_at,
    };
  } catch {
    // Invalid config, credentials, clocks or crypto all leave general admission closed.
    return null;
  }
}
