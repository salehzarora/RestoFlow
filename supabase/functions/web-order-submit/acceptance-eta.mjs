// The negotiated public tuple is informational, never acceptance authority.
const FIELDS = ["preparation_minutes", "accepted_at", "ready_at", "timezone"];
const UTC_INSTANT = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,6}))?(?:Z|\+00:00)$/;

function instant(value) {
  if (typeof value !== "string") return null;
  const match = UTC_INSTANT.exec(value);
  if (!match) return null;
  const [year, month, day, hour, minute, second] = match.slice(1, 7).map(Number);
  if (year < 1 || month < 1 || month > 12 || day < 1 || day > 31 || hour > 23 || minute > 59 || second > 59) return null;
  const date = new Date(0);
  date.setUTCFullYear(year, month - 1, day);
  date.setUTCHours(hour, minute, second, 0);
  if (date.getUTCFullYear() !== year || date.getUTCMonth() !== month - 1 || date.getUTCDate() !== day) return null;
  const fraction = (match[7] ?? "").padEnd(6, "0");
  // PostgreSQL timestamps retain microseconds. Date.parse alone would silently
  // discard them and could accept inconsistent sub-millisecond arithmetic.
  return { micros: BigInt(date.getTime()) * 1000n + BigInt(fraction),
    canonical: `${match[1]}-${match[2]}-${match[3]}T${match[4]}:${match[5]}:${match[6]}.${fraction}Z` };
}

export function projectAcceptanceEta(value) {
  if (value === null || typeof value !== "object" || Array.isArray(value)
    || Object.keys(value).length !== FIELDS.length || !FIELDS.every((key) => Object.hasOwn(value, key))) return null;
  const minutes = value.preparation_minutes;
  if (!Number.isInteger(minutes) || minutes < 1 || minutes > 240) return null;
  const accepted = instant(value.accepted_at); const ready = instant(value.ready_at);
  if (!accepted || !ready || ready.micros - accepted.micros !== BigInt(minutes) * 60_000_000n) return null;
  const zone = value.timezone;
  if (typeof zone !== "string" || zone.length < 1 || zone.length > 100
    || (zone !== "UTC" && !/^[A-Za-z][A-Za-z0-9._+-]*(?:\/[A-Za-z0-9._+-]+)+$/.test(zone))
    || /^(?:posix|right)\//i.test(zone)) return null;
  try { new Intl.DateTimeFormat("en", { timeZone: zone }); } catch { return null; }
  return { preparation_minutes: minutes, accepted_at: accepted.canonical, ready_at: ready.canonical, timezone: zone };
}
