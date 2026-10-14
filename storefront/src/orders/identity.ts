import { RECOVERY_MAX_AGE_MS } from './contract';
import type { RecoveryRecord } from './contract';
import { isCanonicalSlug, isRequestId, isStatusToken, invalid } from './validation';

const ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
/** Exactly 32 random bytes -> canonical, unpadded base64url with zero pad bits. */
function capability(bytes: Uint8Array): string {
  let token = '';
  for (let i = 0; i < bytes.length; i += 3) {
    const word = (bytes[i] << 16) | ((bytes[i + 1] ?? 0) << 8) | (bytes[i + 2] ?? 0);
    token += ALPHABET[(word >>> 18) & 63] + ALPHABET[(word >>> 12) & 63];
    if (i + 1 < bytes.length) token += ALPHABET[(word >>> 6) & 63];
    if (i + 2 < bytes.length) token += ALPHABET[word & 63];
  }
  return token;
}
export class OrderIdentityError extends Error {
  constructor() { super('crypto_unavailable'); this.name = 'OrderIdentityError'; }
}
export function createOrderIdentity(slug: string, now = Date.now(), cryptoImpl: Crypto = globalThis.crypto): RecoveryRecord {
  if (!isCanonicalSlug(slug) || !Number.isSafeInteger(now) || now < 0 || !Number.isSafeInteger(now + RECOVERY_MAX_AGE_MS)) invalid();
  try {
    if (!cryptoImpl || typeof cryptoImpl.randomUUID !== 'function' || typeof cryptoImpl.getRandomValues !== 'function') throw new OrderIdentityError();
    const request_id = cryptoImpl.randomUUID();
    const bytes = new Uint8Array(32);
    cryptoImpl.getRandomValues(bytes);
    const status_token = capability(bytes);
    if (!isRequestId(request_id) || !isStatusToken(status_token)) throw new OrderIdentityError();
    return Object.freeze({ slug, request_id, status_token, created_at: now, expires_at: now + RECOVERY_MAX_AGE_MS });
  } catch { throw new OrderIdentityError(); }
}
