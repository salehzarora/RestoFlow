import { dispatchAuthority, sameDispatchAuthority, dispatchBudget } from "../_shared/pos-order-alert-authority.mjs";

const BASE = "https://oqmevrndtivqxgyvcmwy.supabase.co";
const DISPATCH_URL = `${BASE}/functions/v1/pos-order-alert-dispatch`;
const TIMEOUT_MS = 5000;
const MAX_RESPONSE_BYTES = 4096;

function wakeConfiguration(getEnv, nowMs) {
  if (getEnv("POS_ORDER_ALERT_INSTANT_WAKE_ENABLED") !== "true"
    || getEnv("SUPABASE_URL") !== BASE) return null;
  const worker = getEnv("POS_ORDER_ALERT_WORKER_SECRET");
  if (typeof worker !== "string" || !/^[0-9a-f]{64}(?![\s\S])/.test(worker)) return null;
  const authority = dispatchAuthority(getEnv, nowMs);
  return authority ? { worker, authority } : null;
}

async function wake({ config, getEnv, fetchImpl, now, timeoutMs }) {
  const current = wakeConfiguration(getEnv, now());
  if (!current || current.worker !== config.worker
    || !sameDispatchAuthority(config.authority, getEnv, now())) return;
  const controller = new AbortController();
  let timer;
  let reader;
  try {
    const deadline = new Promise((resolve) => {
      timer = setTimeout(() => { controller.abort(); resolve(); },
        dispatchBudget(config.authority, now(), Math.min(TIMEOUT_MS, timeoutMs)));
    });
    const operation = (async () => {
      const result = await fetchImpl(DISPATCH_URL, {
        method: "POST", headers: { "Content-Type": "application/json", "Authorization": `Bearer ${config.worker}` },
        body: "{}", redirect: "error", cache: "no-store", signal: controller.signal,
      });
      // A transport ignoring abort may return late. Never consume an unbounded body.
      if (controller.signal.aborted || result.status !== 200 || !result.body) {
        if (result.body) void result.body.cancel().catch(() => {});
        return;
      }
      reader = result.body.getReader();
      let size = 0;
      while (!controller.signal.aborted) {
        const { done, value } = await reader.read();
        if (done) break;
        size += value.byteLength;
        if (size > MAX_RESPONSE_BYTES) break;
      }
      // No retry, response forwarding, logs, or assumption of FCM/device delivery.
    })();
    await Promise.race([operation, deadline]);
  } finally {
    clearTimeout(timer);
    controller.abort();
    // Cancellation itself may stall; it must not extend the background budget.
    if (reader) void reader.cancel().catch(() => {});
  }
}

/** Best effort only. Every scheduling/transport failure is isolated from checkout. */
export function scheduleInstantWake({ getEnv, waitUntil, fetchImpl, now, timeoutMs = TIMEOUT_MS }) {
  try {
    if (typeof waitUntil !== "function" || !Number.isFinite(timeoutMs) || timeoutMs <= 0) return;
    const config = wakeConfiguration(getEnv, now());
    if (!config) return;
    let scheduled = false;
    // Defer even fetch startup until the synchronous runtime handoff succeeds.
    const task = Promise.resolve().then(() => scheduled
      ? wake({ config, getEnv, fetchImpl, now, timeoutMs }) : undefined).catch(() => {});
    const handoff = waitUntil(task);
    scheduled = true;
    // Real waitUntil returns void; injected/rejected handoffs are still contained.
    void Promise.resolve(handoff).catch(() => {});
  } catch { /* Missing runtime/configuration and sync scheduling failure are a lost wake, never an order error. */ }
}
