/** Optional welcome media has its own version; legacy image decoders stay strict. */
import { EnvelopeError, type StorefrontMenuFailure } from './decode';
import { decodeStorefrontMenuV11, type StorefrontMenuV11Ok } from './decodeContentV1';

export interface WireWelcomeVideo {
  readonly url: string;
  readonly mime_type: 'video/mp4';
  readonly width: number;
  readonly height: number;
  readonly duration_ms: number;
  readonly bytes: number;
}
export type StorefrontMenuV12Ok = StorefrontMenuV11Ok & {
  readonly restaurant: StorefrontMenuV11Ok['restaurant'] & {
    readonly welcome_media_type: 'image' | 'video' | null;
    readonly welcome_video: WireWelcomeVideo | null;
  };
};
export type StorefrontMenuV12Envelope = StorefrontMenuV12Ok | StorefrontMenuFailure;
const VIDEO_PATH = /^\/storage\/v1\/object\/public\/storefront-welcome-videos\/[0-9a-f]{32}\/[0-9a-f]{64}\.mp4$/;
const reject = (field: string): never => { throw new EnvelopeError(`welcome_video: ${field}`); };

function video(raw: unknown): WireWelcomeVideo | null {
  if (raw === null) return null;
  if (typeof raw !== 'object' || Array.isArray(raw)) return reject('object');
  const r = raw as Record<string, unknown>;
  const keys = ['url', 'mime_type', 'width', 'height', 'duration_ms', 'bytes'];
  if (Object.keys(r).length !== keys.length || !keys.every(k => Object.hasOwn(r, k))) return reject('keys');
  if (typeof r.url !== 'string' || !VIDEO_PATH.test(r.url) || r.mime_type !== 'video/mp4') return reject('public resource');
  const integer = (key: string, max: number) => {
    const n = r[key];
    if (typeof n !== 'number' || !Number.isInteger(n) || n < 1 || n > max) return reject(key);
    return n;
  };
  return { url: r.url, mime_type: 'video/mp4', width: integer('width', 1920), height: integer('height', 1080),
    duration_ms: integer('duration_ms', 30000), bytes: integer('bytes', 20 * 1024 * 1024) };
}

export function decodeStorefrontMenuV12(raw: unknown): StorefrontMenuV12Envelope {
  if (typeof raw !== 'object' || raw === null || Array.isArray(raw)) return reject('envelope');
  const envelope = raw as Record<string, unknown>;
  if (envelope.ok === false) return decodeStorefrontMenuV11(raw) as StorefrontMenuFailure;
  if (typeof envelope.restaurant !== 'object' || envelope.restaurant === null || Array.isArray(envelope.restaurant)) return reject('restaurant');
  const r = envelope.restaurant as Record<string, unknown>;
  if (!Object.hasOwn(r, 'welcome_media_type') || !Object.hasOwn(r, 'welcome_video')) return reject('missing');
  const { welcome_media_type: mode, welcome_video: media, ...restaurant } = r;
  if (mode !== null && mode !== 'image' && mode !== 'video') return reject('mode');
  const selected = video(media);
  if (mode !== 'video' && selected !== null) return reject('inactive video');
  const decoded = decodeStorefrontMenuV11({ ...envelope, restaurant });
  if (!decoded.ok) return decoded;
  return { ...decoded, restaurant: { ...decoded.restaurant, welcome_media_type: mode, welcome_video: selected } };
}
