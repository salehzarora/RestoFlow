// BIZBOT-PAYMENTS-ZCREDIT-PILOT-001E: bounded HTTP helpers shared by the boundary and the three
// transports (caller-scoped client, ledger, provider). Bodies are read with a hard byte cap and a
// deadline while streaming, decoded as strict UTF-8 (a BOM is kept and then refused by the JSON
// grammar, except where a caller opts in to RFC 8259's leniency) and parsed by the strict JSON
// reader. Every upstream call has one deadline for headers and body.
import { parseJson, stringifyJson } from "./json.mjs";

export class BodyError extends Error {}

/** A JSON answer with no-store headers and no CORS (native POS only). */
export function jsonResponse(body, status = 200) {
  return new Response(stringifyJson(body), { status, headers: {
    "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store, max-age=0",
    "Pragma": "no-cache", "Referrer-Policy": "no-referrer", "X-Content-Type-Options": "nosniff",
  } });
}

/** Read a body with a hard byte cap, whatever the declared Content-Length, and an optional deadline. */
export async function readBounded(message, maxBytes, deadlineMs = null) {
  const declared = message.headers.get("content-length");
  if (declared !== null && (!/^[0-9]{1,12}$/.test(declared) || BigInt(declared) > BigInt(maxBytes))) {
    if (message.body) void message.body.cancel().catch(() => {});
    throw new BodyError("too_large");
  }
  if (!message.body) return new Uint8Array();
  const reader = message.body.getReader();
  const chunks = [];
  let size = 0;
  let timer;
  let late = false;
  if (deadlineMs !== null) {
    timer = setTimeout(() => { late = true; void reader.cancel().catch(() => {}); }, deadlineMs);
  }
  try {
    for (;;) {
      const { done, value } = await reader.read();
      if (late) throw new BodyError("too_slow");
      if (done) break;
      size += value.byteLength;
      if (size > maxBytes) {
        void reader.cancel().catch(() => {});
        throw new BodyError("too_large");
      }
      chunks.push(value);
    }
  } finally {
    clearTimeout(timer);
    reader.releaseLock();
  }
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
  return bytes;
}

/** Strict UTF-8 then strict JSON; throws on anything else. `allowBom` ignores one leading BOM. */
export function decodeJson(bytes, { allowBom = false } = {}) {
  let text;
  try { text = new TextDecoder("utf-8", { fatal: true, ignoreBOM: !allowBom }).decode(bytes); } catch { throw new BodyError("utf8"); }
  return parseJson(text);
}

export function delay(ms, signal) {
  return new Promise((resolve) => {
    const timer = setTimeout(resolve, ms);
    signal?.addEventListener("abort", () => { clearTimeout(timer); resolve(); }, { once: true });
  });
}

/**
 * One POST with one deadline for headers and body. Resolves
 *   { kind: 'answer', status, value } - an HTTP answer whose whole body arrived; value is the parsed
 *                                        JSON, or null when the body is oversized or not strict JSON
 *   { kind: 'failure' }               - no complete answer: network error, deadline, redirect, a body cut off
 * Never throws and never retries.
 */
export async function postJson(fetchImpl, url, headers, body, { deadlineMs, maxBytes, allowBom = false }) {
  const controller = new AbortController();
  let timer;
  const deadline = new Promise((resolve) => {
    timer = setTimeout(() => { controller.abort(); resolve({ kind: "failure" }); }, deadlineMs);
  });
  const attempt = (async () => {
    try {
      const response = await fetchImpl(url, { method: "POST", headers, body, redirect: "error", cache: "no-store",
        signal: controller.signal });
      if (controller.signal.aborted) {
        if (response.body) void response.body.cancel().catch(() => {});
        return { kind: "failure" };
      }
      let bytes;
      try {
        bytes = await readBounded(response, maxBytes);
      } catch (error) {
        return error instanceof BodyError && !controller.signal.aborted
          ? { kind: "answer", status: response.status, value: null } : { kind: "failure" };
      }
      if (controller.signal.aborted) return { kind: "failure" };
      let value = null;
      try { value = decodeJson(bytes, { allowBom }); } catch { value = null; }
      return { kind: "answer", status: response.status, value };
    } catch {
      return { kind: "failure" };
    }
  })();
  try {
    return await Promise.race([attempt, deadline]);
  } finally {
    clearTimeout(timer);
    controller.abort();
  }
}
