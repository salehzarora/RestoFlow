import type { AcceptanceEta } from './contract';
import { exactObject, invalid } from './validation';

/** Exact UTC microseconds: PostgreSQL precision must not be rounded for binding. */
function instant(value: unknown): bigint {
  if (typeof value !== 'string') return invalid();
  const match = /^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})(?:\.(\d{1,6}))?(?:Z|\+00:00)$/.exec(value);
  if (!match || Number(match[1].slice(0, 4)) < 1) return invalid();
  const millis = Date.parse(`${match[1]}Z`);
  if (!Number.isFinite(millis) || new Date(millis).toISOString().slice(0, 19) !== match[1]) return invalid();
  return BigInt(millis) * BigInt(1000) + BigInt((match[2] ?? '').padEnd(6, '0'));
}
function canonicalUtc(value: string): string {
  const match = /^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})(?:\.(\d{1,6}))?(?:Z|\+00:00)$/.exec(value)!;
  return `${match[1]}.${(match[2] ?? '').padEnd(6, '0')}Z`;
}

export function decodeAcceptanceEta(value: unknown): AcceptanceEta {
  const eta = exactObject(value, ['preparation_minutes', 'accepted_at', 'ready_at', 'timezone']);
  const minutes = eta.preparation_minutes;
  if (typeof minutes !== 'number' || !Number.isInteger(minutes) || minutes < 1 || minutes > 240) return invalid();
  if (instant(eta.ready_at) - instant(eta.accepted_at) !== BigInt(minutes) * BigInt(60_000_000)) return invalid();
  if (typeof eta.timezone !== 'string' || eta.timezone.length > 100 || (eta.timezone !== 'UTC' && !/^[A-Za-z][A-Za-z0-9._+-]*(?:\/[A-Za-z0-9._+-]+)+$/.test(eta.timezone)) || /^(?:posix|right)\//i.test(eta.timezone)) return invalid();
  try { new Intl.DateTimeFormat('en', { timeZone: eta.timezone }).format(0); } catch { return invalid(); }
  return Object.freeze({ preparation_minutes: minutes, accepted_at: canonicalUtc(eta.accepted_at as string), ready_at: canonicalUtc(eta.ready_at as string), timezone: eta.timezone });
}
