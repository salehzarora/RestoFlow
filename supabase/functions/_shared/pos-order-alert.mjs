// BIZBOT-POS-BACKGROUND-ORDER-ALERT-001: bounded, secret-safe internal transport.
import { parseStrictJson, readLimitedBody } from "../web-order-submit/json.mjs";
export const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
export const HEX_SECRET = /^[0-9a-f]{64}$/;
export const timestamp = (value) => typeof value === "string" && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$/.test(value) && Number.isFinite(Date.parse(value));
export const object = (value) => value !== null && typeof value === "object" && !Array.isArray(value);
export function response(body, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: {
    "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store, max-age=0",
    "Pragma": "no-cache", "Referrer-Policy": "no-referrer", "X-Content-Type-Options": "nosniff",
  } });
}
export async function readJson(message, limit = 2048) {
  return parseStrictJson(new TextDecoder("utf-8", { fatal: true }).decode(await readLimitedBody(message, limit)));
}
export async function hash(value, cryptoImpl = globalThis.crypto) {
  return [...new Uint8Array(await cryptoImpl.subtle.digest("SHA-256", new TextEncoder().encode(value)))]
    .map((v) => v.toString(16).padStart(2, "0")).join("");
}
export async function constantSecret(actual, expected, cryptoImpl = globalThis.crypto) {
  if (!HEX_SECRET.test(actual ?? "") || !HEX_SECRET.test(expected ?? "")) return false;
  const a = await hash(actual, cryptoImpl); const b = await hash(expected, cryptoImpl);
  let different = 0; for (let i = 0; i < a.length; i++) different |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return different === 0;
}
export function configuration(getEnv) {
  const base = getEnv("SUPABASE_URL"); const key = getEnv("SUPABASE_SERVICE_ROLE_KEY");
  if (!base || !key) return null;
  let url; try { url = new URL(base); } catch { return null; }
  const local = url.protocol === "http:" && (["localhost", "127.0.0.1", "[::1]"].includes(url.hostname) || (url.hostname === "kong" && url.port === "8000"));
  if ((url.protocol !== "https:" && !local) || url.username || url.password || url.search || url.hash || !["", "/"].includes(url.pathname)) return null;
  return { base: url.origin, key };
}
export async function boundedFetch(url, init, fetchImpl, timeoutMs = 5000) {
  const controller = new AbortController(); let timer;
  try {
    return await Promise.race([
      fetchImpl(url, { ...init, redirect: "error", cache: "no-store", signal: controller.signal }),
      new Promise((_, reject) => { timer = setTimeout(() => { controller.abort(); reject(new Error("upstream_timeout")); }, timeoutMs); }),
    ]);
  } finally { clearTimeout(timer); }
}
export async function rpc(name, body, config, fetchImpl, timeoutMs = 5000) {
  const result = await boundedFetch(`${config.base}/rest/v1/rpc/${name}`, { method: "POST", headers: {
    "Content-Type": "application/json", "Accept": "application/json", "Accept-Profile": "public", "Content-Profile": "public",
    "apikey": config.key, "Authorization": `Bearer ${config.key}`,
  }, body: JSON.stringify(body) }, fetchImpl, timeoutMs);
  if (!result.ok) { if (result.body) void result.body.cancel().catch(() => {}); throw new Error("rpc_unavailable"); }
  return readJson(result, 32768);
}
