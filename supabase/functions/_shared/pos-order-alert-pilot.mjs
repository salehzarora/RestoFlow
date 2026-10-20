// BIZBOT-INSTANT-NOTIFICATION-WAKE-001: shared Edge-side dispatch authority.
// No defaults or rolling windows. Vercel keeps its independent outer gate.
const MAX_PILOT_MS = 30 * 60 * 1000;
function utcTimestamp(value) {
  if (typeof value !== "string"
    || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{3})?Z(?![\s\S])/.test(value)) return NaN;
  const timestamp = Date.parse(value);
  const canonical = value.length === 20 ? `${value.slice(0, -1)}.000Z` : value;
  return Number.isFinite(timestamp) && new Date(timestamp).toISOString() === canonical ? timestamp : NaN;
}

export function dispatchPilot(getEnv, nowMs) {
  if (getEnv("POS_ORDER_ALERTS_ENABLED") !== "true") return null;
  const start = utcTimestamp(getEnv("POS_ALERT_PILOT_START_UTC"));
  const end = utcTimestamp(getEnv("POS_ALERT_PILOT_END_UTC"));
  if (!Number.isFinite(nowMs) || !Number.isFinite(start) || !Number.isFinite(end)
    || start >= end || end - start > MAX_PILOT_MS || nowMs < start || nowMs >= end) return null;
  return { start, end };
}

// A changed/extended window cannot renew an invocation already in flight.
export function sameDispatchPilot(pilot, getEnv, nowMs) {
  const current = dispatchPilot(getEnv, nowMs);
  return current !== null && current.start === pilot.start && current.end === pilot.end;
}
