/**
 * Versioned Home-content read boundary. The original menu decoder stays strict
 * and unchanged: old clients continue to use storefront_menu. Only the new
 * companion response may carry this exact, bounded public-text object.
 */
import { decodeStorefrontMenu, EnvelopeError, type StorefrontMenuFailure, type StorefrontMenuOk } from './decode';

export interface WireHomeContent {
  readonly hero_headline: string | null;
  readonly hero_subline: string | null;
  readonly announcement_text: string | null;
}

export interface StorefrontMenuV2Ok extends StorefrontMenuOk {
  readonly home_content: WireHomeContent;
}

export type StorefrontMenuV2Envelope = StorefrontMenuV2Ok | StorefrontMenuFailure;

const KEYS = ['hero_headline', 'hero_subline', 'announcement_text'] as const;
const reject = (reason: string): never => { throw new EnvelopeError(`home_content: ${reason}`); };

function text(value: unknown, field: string, max: number): string | null {
  if (value === null) return null;
  if (typeof value !== 'string' || value === '' || [...value].length > max || /[\u0000-\u001f\u007f]/.test(value)) {
    return reject(`${field}: invalid public text`);
  }
  return value;
}

export function decodeStorefrontMenuV2(raw: unknown): StorefrontMenuV2Envelope {
  if (typeof raw !== 'object' || raw === null || Array.isArray(raw)) return reject('not an object');
  const envelope = raw as Record<string, unknown>;
  // The old decoder enforces the complete, unchanged failure key set too.
  if (envelope.ok === false) return decodeStorefrontMenu(envelope) as StorefrontMenuFailure;
  if (!Object.hasOwn(envelope, 'home_content')) return reject('missing');
  const { home_content: content, ...menu } = envelope;
  const decoded = decodeStorefrontMenu(menu);
  if (!decoded.ok) return decoded;
  if (typeof content !== 'object' || content === null || Array.isArray(content)) return reject('not an object');
  const record = content as Record<string, unknown>;
  const keys = Object.keys(record).sort();
  const expected = [...KEYS].sort();
  if (keys.length !== expected.length || keys.some((key, index) => key !== expected[index])) return reject('unexpected keys');
  return {
    ...decoded,
    home_content: {
      hero_headline: text(record.hero_headline, 'hero_headline', 120),
      hero_subline: text(record.hero_subline, 'hero_subline', 180),
      announcement_text: text(record.announcement_text, 'announcement_text', 240),
    },
  };
}
