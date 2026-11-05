// Scope and association checks for the optional, generation-bound menu background.
import { releaseOwned, sourceMaxBytes } from './recipe.mjs';
import { privateSourceInScope } from './validate.mjs';
import { BACKGROUND_RECIPE } from './background-bilinear.mjs';

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$(?![\s\S])/;
const HASH = /^[0-9a-f]{64}$(?![\s\S])/;
const dimension = n => Number.isInteger(n) && n >= 1 && n <= 960;

export function validBackgroundSource(row, request) {
  return row.base_media_id === request.baseMediaId && typeof row.base_hash === 'string' && HASH.test(row.base_hash)
    && dimension(row.base_width) && dimension(row.base_height)
    && sourceMaxBytes(row.source_bucket) !== null
    && privateSourceInScope(row.source_bucket, row.source_key, request.organizationId, request.restaurantId, request.branchId);
}

// A source association predates the companion registry. Verify what its current
// private bytes actually produce, without claiming historical byte identity.
export async function checkBackgroundBase(deriver, bytes, source, rung) {
  const base = await deriver.derive(bytes, { variant: 'w960', source: source.source_bucket, rung });
  if (base.status !== 'derived') return 'base_mismatch';
  const matches = base.sha256 === source.base_hash && base.width === source.base_width && base.height === source.base_height;
  releaseOwned(base.bytes);
  if (!matches) return 'base_mismatch';
  return Math.max(base.source.width, base.source.height) <= 960 ? 'not_needed' : 'verified';
}

export async function backgroundObjectKey(restaurantId, hash) {
  const seed = new TextEncoder().encode('storefront-menu-background-v1:' + restaurantId);
  const digest = new Uint8Array(await crypto.subtle.digest('SHA-256', seed));
  const prefix = Array.from(digest.subarray(0, 16), byte => byte.toString(16).padStart(2, '0')).join('');
  return prefix + '/' + hash + '.webp';
}

export function matchesBackgroundRegistration(row, baseMediaId, derivative, expectedKey) {
  return typeof row.variant_id === 'string' && UUID.test(row.variant_id) && row.base_media_id === baseMediaId
    && row.object_key === expectedKey && row.content_hash === derivative.sha256 && row.width === derivative.width
    && row.height === derivative.height && row.bytes === derivative.byteLength
    && row.recipe === BACKGROUND_RECIPE.id && row.variant === BACKGROUND_RECIPE.variant && (row.state === 'staged' || row.state === 'published');
}
