import { createHash, timingSafeEqual } from 'node:crypto';

export const DISPATCH_URL = 'https://oqmevrndtivqxgyvcmwy.supabase.co/functions/v1/pos-order-alert-dispatch';
export const TIMEOUT_MS = 115_000;
const MAX_RESPONSE_BYTES = 4096;
const MAX_PILOT_MS = 30 * 60 * 1000;
function utcTimestamp(value) {
  if (typeof value !== 'string'
    || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{3})?Z(?![\s\S])/.test(value)) return NaN;
  const timestamp = Date.parse(value);
  const canonical = value.length === 20 ? `${value.slice(0, -1)}.000Z` : value;
  // Date.parse normalizes some impossible dates; round-trip instead of accepting them.
  return Number.isFinite(timestamp) && new Date(timestamp).toISOString() === canonical ? timestamp : NaN;
}
// Both secrets are independently generated 256-bit lowercase hex bearers.
const bearer = (value) => typeof value === 'string' && /^[0-9a-f]{64}(?![\s\S])/.test(value);
const equal = (a, b) => timingSafeEqual(
  createHash('sha256').update(a).digest(),
  createHash('sha256').update(b).digest(),
);
const reply = (status, error) => Response.json(error ? { ok: false, error } : { ok: true }, {
  status,
  headers: { 'Cache-Control': 'no-store' },
});

async function successfulResponse(response) {
  if (response.status !== 200 || !response.body) return false;
  const reader = response.body.getReader();
  const chunks = [];
  let size = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > MAX_RESPONSE_BYTES) return false;
      chunks.push(value);
    }
    const bytes = new Uint8Array(size);
    let offset = 0;
    for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
    const result = JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(bytes));
    return result?.ok === true
      && Number.isInteger(result.sent) && result.sent >= 0
      && Number.isInteger(result.deferred) && result.deferred >= 0
      && result.sent + result.deferred <= 10;
  } finally {
    // Discard upstream content, including errors; never proxy or log it.
    await reader.cancel().catch(() => {});
  }
}

export function createHandler({
  getEnv = (name) => process.env[name],
  fetchImpl = globalThis.fetch,
  timeoutMs = TIMEOUT_MS,
  now = () => Date.now(),
} = {}) {
  return async function handler(request) {
    let timedOut = false;
    let timer;
    let controller;
    try {
      if (request.method !== 'GET') return reply(405, 'method_not_allowed');
      const inbound = getEnv('CRON_SECRET');
      if (!bearer(inbound)) return reply(503, 'unavailable');
      const authorization = request.headers.get('authorization') ?? '';
      const supplied = authorization.startsWith('Bearer ') ? authorization.slice(7) : '';
      if (!bearer(supplied) || !equal(supplied, inbound)) return reply(401, 'unauthorized');
      if (new URL(request.url).search || request.body !== null) return reply(400, 'invalid_request');
      if (getEnv('POS_ALERT_CRON_ENABLED') !== 'true') return reply(503, 'disabled');
      if (getEnv('VERCEL') !== '1' || getEnv('VERCEL_ENV') !== 'production') return reply(503, 'unavailable');
      const outbound = getEnv('POS_ORDER_ALERT_WORKER_SECRET');
      if (!bearer(outbound) || equal(inbound, outbound)
        || getEnv('POS_ALERT_DISPATCH_URL') !== DISPATCH_URL) return reply(503, 'unavailable');
      const currentTime = now();
      const mode = getEnv('POS_ORDER_ALERT_MODE') ?? 'continuous';
      if (!Number.isFinite(currentTime) || !['continuous', 'pilot'].includes(mode)) return reply(503, 'unavailable');
      let budget = timeoutMs;
      if (mode === 'pilot') {
        const pilotStart = utcTimestamp(getEnv('POS_ALERT_PILOT_START_UTC'));
        const pilotEnd = utcTimestamp(getEnv('POS_ALERT_PILOT_END_UTC'));
        if (!Number.isFinite(pilotStart) || !Number.isFinite(pilotEnd)
          || pilotStart >= pilotEnd || pilotEnd - pilotStart > MAX_PILOT_MS
          || currentTime < pilotStart || currentTime >= pilotEnd) return reply(503, 'unavailable');
        budget = Math.min(budget, pilotEnd - currentTime);
      }

      controller = new AbortController();
      let expire;
      const deadline = new Promise((resolve) => { expire = resolve; });
      timer = setTimeout(() => {
        timedOut = true;
        controller.abort();
        expire(false);
      }, budget);
      // Exactly one POST per invocation. Database leases/idempotency, not
      // process-local locks, protect concurrent or duplicate Cron invocations.
      const operation = (async () => {
        const upstream = await fetchImpl(DISPATCH_URL, {
          method: 'POST',
          headers: { Authorization: `Bearer ${outbound}`, 'Content-Type': 'application/json' },
          body: '{}',
          redirect: 'error',
          cache: 'no-store',
          signal: controller.signal,
        });
        return successfulResponse(upstream);
      })();
      const success = await Promise.race([operation, deadline]);
      if (timedOut) return reply(504, 'upstream_timeout');
      return success ? reply(200) : reply(502, 'upstream_unavailable');
    } catch {
      // Do not log exceptions, request headers, env values or upstream bodies.
      return timedOut ? reply(504, 'upstream_timeout') : reply(502, 'upstream_unavailable');
    } finally {
      clearTimeout(timer);
      // Also terminate unread error bodies and release their connection.
      controller?.abort();
    }
  };
}
