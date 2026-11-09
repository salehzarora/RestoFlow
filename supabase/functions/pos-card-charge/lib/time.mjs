// BIZBOT-PAYMENTS-ZCREDIT-PILOT-001E: database timestamps for the poll cadence (not money).
// Both instants come from the same database clock (the adapter read's server_ts and
// last_lookup_at), so the function's own clock never decides the cadence.

const TS = /^([0-9]{4})-([0-9]{2})-([0-9]{2})[T ]([0-9]{2}):([0-9]{2}):([0-9]{2})(?:\.([0-9]{1,6}))?(Z|([+-])([0-9]{2}):?([0-9]{2})?)$/;

/** Milliseconds since the epoch of a PostgreSQL timestamptz text, or null. */
export function timestampMs(text) {
  const match = typeof text === "string" ? TS.exec(text) : null;
  if (!match) return null;
  const [year, month, day, hour, minute, second] = match.slice(1, 7).map((part) => Number.parseInt(part, 10));
  if (month < 1 || month > 12 || day < 1 || day > 31 || hour > 23 || minute > 59 || second > 59) return null;
  const millis = match[7] ? Number.parseInt(match[7].padEnd(3, "0").slice(0, 3), 10) : 0;
  const offset = match[8] === "Z" ? 0
    : (match[9] === "-" ? -1 : 1) * (Number.parseInt(match[10], 10) * 60 + Number.parseInt(match[11] ?? "0", 10));
  return Date.UTC(year, month - 1, day, hour, minute, second, millis) - offset * 60_000;
}
