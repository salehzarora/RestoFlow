/** Versioned public featured selection. The server must redact private IDs
 * before serialization; this subset check is an additional consumer guard. */
import { EnvelopeError, type StorefrontMenuFailure } from './decode';
import { decodeStorefrontMenuV2, type StorefrontMenuV2Ok } from './decodeHomeContent';

export interface StorefrontMenuV3Ok extends StorefrontMenuV2Ok {
  readonly featured_item_ids: readonly string[];
}

export type StorefrontMenuV3Envelope = StorefrontMenuV3Ok | StorefrontMenuFailure;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const reject = (): never => { throw new EnvelopeError('featured_item_ids: invalid public selection'); };

export function decodeStorefrontMenuV3(raw: unknown): StorefrontMenuV3Envelope {
  if (typeof raw !== 'object' || raw === null || Array.isArray(raw)) return reject();
  const envelope = raw as Record<string, unknown>;
  if (envelope.ok === false) return decodeStorefrontMenuV2(envelope) as StorefrontMenuFailure;
  if (!Object.hasOwn(envelope, 'featured_item_ids')) return reject();
  const { featured_item_ids: selected, ...base } = envelope;
  const decoded = decodeStorefrontMenuV2(base);
  if (!decoded.ok) return reject();
  if (!Array.isArray(selected) || selected.length > 12) return reject();
  const served = new Set(decoded.items.map((item) => item.id));
  const seen = new Set<string>();
  for (const id of selected) {
    if (typeof id !== 'string' || id.length !== 36 || !UUID.test(id) || !served.has(id) || seen.has(id)) return reject();
    seen.add(id);
  }
  return { ...decoded, featured_item_ids: Object.freeze([...seen]) };
}
