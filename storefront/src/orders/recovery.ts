import { RECOVERY_MAX_AGE_MS } from './contract';
import type { RecoveryRecord, RecoveryStorage } from './contract';
import { exactObject, invalid, isCanonicalSlug, isRequestId, isStatusToken } from './validation';
import { parseOrderJson } from './json';

export type RecoveryRead =
  | { readonly kind: 'record'; readonly record: RecoveryRecord }
  | { readonly kind: 'missing' | 'invalid' | 'expired' | 'blocked' };
export function recoveryKey(slug: string): string {
  if (!isCanonicalSlug(slug)) invalid();
  return `bizbot:web-order:${slug}`;
}
/** Called only from controller actions, never during rendering or server evaluation. */
export function browserRecoveryStorage(): RecoveryStorage | null {
  try { return typeof window === 'undefined' ? null : window.sessionStorage; } catch { return null; }
}

function decodeRecord(source: string, slug: string, now: number): RecoveryRecord {
  if (source.length > 1024 || !Number.isSafeInteger(now) || now < 0) invalid();
  const value = exactObject(parseOrderJson(source), ['slug', 'request_id', 'status_token', 'created_at', 'expires_at']);
  if (value.slug !== slug || !isCanonicalSlug(value.slug) || !isRequestId(value.request_id) || !isStatusToken(value.status_token)) invalid();
  const created = value.created_at;
  const expires = value.expires_at;
  if (typeof created !== 'number' || typeof expires !== 'number' || !Number.isSafeInteger(created) || !Number.isSafeInteger(expires) || created < 0 || created > now || expires <= created || expires > created + RECOVERY_MAX_AGE_MS) invalid();
  return Object.freeze({ slug, request_id: value.request_id, status_token: value.status_token, created_at: created, expires_at: expires });
}
export function clearRecovery(storage: RecoveryStorage | null, slug: string): boolean {
  try { if (!storage) return false; storage.removeItem(recoveryKey(slug)); return storage.getItem(recoveryKey(slug)) === null; } catch { return false; }
}
export function readRecovery(storage: RecoveryStorage | null, slug: string, now = Date.now()): RecoveryRead {
  let source: string | null;
  try { if (!storage) return { kind: 'blocked' }; source = storage.getItem(recoveryKey(slug)); } catch { return { kind: 'blocked' }; }
  if (source === null) return { kind: 'missing' };
  let record: RecoveryRecord;
  try { record = decodeRecord(source, slug, now); }
  catch { return { kind: clearRecovery(storage, slug) ? 'invalid' : 'blocked' }; }
  if (record.expires_at <= now) return { kind: clearRecovery(storage, slug) ? 'expired' : 'blocked' };
  return { kind: 'record', record };
}
/** Store an explicit projection and verify the write. No cart/contact/payload is retained. */
export function saveRecovery(storage: RecoveryStorage | null, record: RecoveryRecord, now = Date.now()): boolean {
  try {
    if (!storage) return false;
    const source = JSON.stringify({ slug: record.slug, request_id: record.request_id, status_token: record.status_token, created_at: record.created_at, expires_at: record.expires_at });
    const decoded = decodeRecord(source, record.slug, now);
    if (decoded.expires_at <= now) return false;
    storage.setItem(recoveryKey(record.slug), source);
    return storage.getItem(recoveryKey(record.slug)) === source;
  } catch { return false; }
}
