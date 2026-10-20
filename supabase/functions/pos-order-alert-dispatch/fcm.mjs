import { boundedFetch, readJson, object, UUID, timestamp } from "../_shared/pos-order-alert.mjs";
// Assemble marker syntax; no private key material is present in source.
const PEM_BEGIN = ["-----BEGIN", "PRIVATE KEY-----"].join(" ");
const PEM_END = ["-----END", "PRIVATE KEY-----"].join(" ");
const encode = (bytes) => btoa(String.fromCharCode(...bytes)).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
const json64 = (value) => encode(new TextEncoder().encode(JSON.stringify(value)));
export function serviceAccount(source) {
  if (typeof source !== "string" || source.length > 16384) return null;
  let value; try { value = JSON.parse(source); } catch { return null; }
  if (!object(value) || value.type !== "service_account" || !/^[a-z][a-z0-9-]{4,61}[a-z0-9]$/.test(value.project_id ?? "")
    || !/^[a-zA-Z0-9._-]+@[a-z0-9-]+\.iam\.gserviceaccount\.com$/.test(value.client_email ?? "")
    || typeof value.private_key !== "string" || !value.private_key.startsWith(PEM_BEGIN)
    || value.token_uri !== "https://oauth2.googleapis.com/token") return null;
  return { projectId: value.project_id, email: value.client_email, privateKey: value.private_key };
}
export async function accessToken(account, { fetchImpl, cryptoImpl, now, timeoutMs }) {
  const issued = Math.floor(now() / 1000);
  const unsigned = `${json64({ alg: "RS256", typ: "JWT" })}.${json64({ iss: account.email,
    scope: "https://www.googleapis.com/auth/firebase.messaging", aud: "https://oauth2.googleapis.com/token", iat: issued, exp: issued + 3600 })}`;
  const pem = account.privateKey.replaceAll(PEM_BEGIN, "").replaceAll(PEM_END, "").replace(/\s/g, "");
  const key = await cryptoImpl.subtle.importKey("pkcs8", Uint8Array.from(atob(pem), (c) => c.charCodeAt(0)),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
  const signature = await cryptoImpl.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(unsigned));
  const body = await boundedFetch("https://oauth2.googleapis.com/token", { method: "POST", headers: {
    "Content-Type": "application/x-www-form-urlencoded",
  }, body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion: `${unsigned}.${encode(new Uint8Array(signature))}` }) }, fetchImpl, timeoutMs, async (result) => {
    if (!result.ok) { if (result.body) void result.body.cancel().catch(() => {}); throw new Error("oauth_unavailable"); }
    return readJson(result, 16384);
  });
  if (!object(body) || typeof body.access_token !== "string" || !/^[A-Za-z0-9._~-]{20,4096}$/.test(body.access_token)
    || body.token_type !== "Bearer" || !Number.isInteger(body.expires_in) || body.expires_in < 1 || body.expires_in > 3600) throw new Error("oauth_invalid");
  return body.access_token;
}
export function message(delivery, nowMs) {
  if (!object(delivery) || !UUID.test(delivery.delivery_id ?? "") || !UUID.test(delivery.lease_id ?? "")
    || !UUID.test(delivery.registration_id ?? "") || !UUID.test(delivery.generation ?? "")
    || !UUID.test(delivery.request_id ?? "") || !["pending", "terminal"].includes(delivery.kind)
    || !timestamp(delivery.expires_at) || !timestamp(delivery.authority_expires_at)
    || typeof delivery.fcm_token !== "string" || !/^[^\s\x00-\x1f\x7f]{20,4096}$/.test(delivery.fcm_token)) throw new Error("invalid_delivery");
  const remaining = Math.floor((Math.min(Date.parse(delivery.authority_expires_at),
    delivery.kind === "pending" ? Date.parse(delivery.expires_at) : nowMs + 60_000) - nowMs) / 1000);
  if (remaining < 1) return null;
  return { message: { token: delivery.fcm_token,
    data: { version: "1", kind: delivery.kind === "pending" ? "pending" : "cancel", request_id: delivery.request_id,
      expires_at: delivery.expires_at, registration_id: delivery.registration_id },
    // A terminal event must never replace another request's only pending wake
    // while Android is disconnected/closed. Each kind still coalesces hints;
    // native reconciles the complete authoritative set before playing sound.
    android: { priority: "HIGH", ttl: `${Math.min(remaining, 120)}s`,
      collapse_key: delivery.kind === "pending" ? "bizbot_pending_orders" : "bizbot_resolved_orders" },
  } };
}
export async function send(account, token, delivery, { fetchImpl, now, timeoutMs }) {
  const payload = message(delivery, now());
  if (!payload) return "permanent_failure";
  return boundedFetch(`https://fcm.googleapis.com/v1/projects/${account.projectId}/messages:send`, {
    method: "POST", headers: { "Content-Type": "application/json", "Authorization": `Bearer ${token}` },
    body: JSON.stringify(payload),
  }, fetchImpl, timeoutMs, async (result) => {
  if (result.ok) {
    const body = await readJson(result, 16384);
    return object(body) && typeof body.name === "string" && body.name.startsWith(`projects/${account.projectId}/messages/`) ? "sent" : "retry";
  }
  let code; try {
    const body = await readJson(result, 16384);
    code = body?.error?.details?.find((row) => row?.["@type"] === "type.googleapis.com/google.firebase.fcm.v1.FcmError")?.errorCode;
  } catch { /* Error response details are never logged or returned. */ }
  if (code === "UNREGISTERED") return "invalid_token";
  if ([408, 429, 500, 502, 503, 504].includes(result.status)) return "retry";
  return "permanent_failure";
  });
}
