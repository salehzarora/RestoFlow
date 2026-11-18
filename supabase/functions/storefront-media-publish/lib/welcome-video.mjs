// BIZBOT-STOREFRONT-WELCOME-VIDEO-PUBLISH-001. Explicit owner action only.
// Existing caller-JWT Auth/RPC/Storage transport; no image-engine initialization.
import { UpstreamError } from './caller.mjs';
import { validateWelcomeMp4, WelcomeVideoRejected, WELCOME_VIDEO_LIMITS } from './welcome-mp4.mjs';

const PRIVATE_BUCKET = 'storefront-welcome-video-originals';
const PUBLIC_BUCKET = 'storefront-welcome-videos';
const ENTITY = 'storefront_welcome_video';
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const HASH = /^[0-9a-f]{64}$/;
const OBJECT = /^[0-9a-f]{32}\/[0-9a-f]{64}\.mp4$/;
const REQUEST_KEYS = ['kind', 'request_id', 'organization_id', 'restaurant_id', 'source_key'];
const MEDIA_KEYS = ['id', 'object_key', 'content_hash', 'mime_type', 'width', 'height', 'duration_ms', 'bytes', 'published', 'url'];
const sourceKeyPattern = /^([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\.mp4$/;
const record = v => v !== null && typeof v === 'object' && !Array.isArray(v);
const exactKeys = (v, keys) => record(v) && Object.keys(v).length === keys.length && Object.keys(v).every(k => keys.includes(k));
const hashBytes = async bytes => Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', bytes)), b => b.toString(16).padStart(2, '0')).join('');

export function validateWelcomeVideoRequest(body) {
  if (!record(body)) return { ok: false, field: 'body', reason: 'type' };
  const unknown = Object.keys(body).find(k => !REQUEST_KEYS.includes(k));
  if (unknown || !exactKeys(body, REQUEST_KEYS)) return { ok: false, field: unknown && REQUEST_KEYS.includes(unknown) ? unknown : 'body', reason: 'keys' };
  if (body.kind !== 'welcome_video_v1') return { ok: false, field: 'kind', reason: 'value' };
  for (const key of ['request_id', 'organization_id', 'restaurant_id']) {
    if (typeof body[key] !== 'string' || !UUID.test(body[key])) return { ok: false, field: key, reason: 'value' };
  }
  const key = typeof body.source_key === 'string' ? sourceKeyPattern.exec(body.source_key) : null;
  if (!key || key[1] !== body.organization_id || key[2] !== body.restaurant_id) return { ok: false, field: 'source_key', reason: 'scope' };
  return { ok: true, value: Object.freeze({ requestId: body.request_id, organizationId: body.organization_id, restaurantId: body.restaurant_id, sourceKey: body.source_key }) };
}

function validMedia(media, expected, published = null) {
  if (!exactKeys(media, MEDIA_KEYS) || typeof media.id !== 'string' || !UUID.test(media.id)
      || typeof media.object_key !== 'string' || !OBJECT.test(media.object_key)
      || typeof media.content_hash !== 'string' || !HASH.test(media.content_hash)
      || media.object_key.slice(33, 97) !== media.content_hash || media.mime_type !== 'video/mp4'
      || !Number.isInteger(media.width) || media.width < 1 || media.width > WELCOME_VIDEO_LIMITS.width
      || !Number.isInteger(media.height) || media.height < 1 || media.height > WELCOME_VIDEO_LIMITS.height
      || !Number.isInteger(media.duration_ms) || media.duration_ms < 1 || media.duration_ms > WELCOME_VIDEO_LIMITS.durationMs
      || !Number.isInteger(media.bytes) || media.bytes < 1 || media.bytes > WELCOME_VIDEO_LIMITS.bytes
      || typeof media.published !== 'boolean' || (published !== null && media.published !== published)) return false;
  const path = `/storage/v1/object/public/${PUBLIC_BUCKET}/${media.object_key}`;
  for (const [key, value] of Object.entries(media)) if (key === 'url' && value !== (media.published ? path : null)) return false;
  return !expected || (media.content_hash === expected.hash && media.width === expected.width && media.height === expected.height
    && media.duration_ms === expected.durationMs && media.bytes === expected.byteLength);
}

/** Runs only after the existing handler has verified the signed-in principal. */
export async function publishWelcomeVideo(body, caller, { reply, fail, logError }) {
  let effects = false;
  const upstream = error => {
    if (!(error instanceof UpstreamError)) throw error;
    if (error.kind === 'unauthenticated') return fail(401, 'unauthenticated');
    if (error.kind === 'forbidden') return fail(403, 'permission_denied');
    if (error.kind === 'not_found') return fail(404, 'source_not_found');
    if (error.kind === 'rejected' && error.code === 'request_id_reused') return fail(409, 'restart_required');
    return fail(error.kind === 'rejected' ? 500 : 503, error.kind === 'rejected' ? 'internal_error' : 'upstream_unavailable', { retryable: true, uncertain: effects });
  };
  const refusedRpc = value => {
    const errorKeys = value?.error === 'invalid' ? ['ok', 'entity', 'error', 'field'] : ['ok', 'entity', 'error'];
    if (!exactKeys(value, errorKeys) || value.ok !== false || value.entity !== ENTITY) return fail(500, 'internal_error', { retryable: true, uncertain: effects });
    switch (value.error) {
      case 'permission_denied': return fail(403, 'permission_denied');
      case 'invalid': {
        const fields = ['organization_id', 'restaurant_id', 'source_key', 'request_id', 'content_hash', 'width', 'height', 'duration_ms', 'bytes', 'media_id'];
        return fail(400, 'invalid_request', { field: fields.includes(value.field) ? value.field : 'body', reason: 'upstream_invalid' });
      }
      case 'not_found': return fail(404, 'source_not_found');
      case 'source_unavailable': return fail(422, 'refused', { code: 'source_unavailable' });
      case 'request_mismatch': return fail(409, 'restart_required');
      case 'object_unavailable': return fail(503, 'upstream_unavailable', { retryable: true, uncertain: effects });
      default: return fail(500, 'internal_error', { retryable: true, uncertain: effects });
    }
  };
  try {
    const validation = validateWelcomeVideoRequest(body);
    if (!validation.ok) return fail(400, 'invalid_request', { field: validation.field, reason: validation.reason });
    const r = validation.value;
    const scope = { p_organization_id: r.organizationId, p_restaurant_id: r.restaurantId, p_source_key: r.sourceKey, p_request_id: r.requestId };
    let preflight;
    try { preflight = await caller.rpc('preflight_storefront_welcome_video_v1', scope); } catch (e) { return upstream(e); }
    if (preflight.ok !== true) return refusedRpc(preflight);
    const source = preflight.source;
    if (!exactKeys(preflight, ['ok', 'entity', 'source', 'media']) || preflight.entity !== ENTITY
        || !exactKeys(source, ['bucket', 'key', 'bytes', 'mime_type']) || source.bucket !== PRIVATE_BUCKET || source.key !== r.sourceKey
        || source.mime_type !== 'video/mp4' || !Number.isInteger(source.bytes) || source.bytes < 1 || source.bytes > WELCOME_VIDEO_LIMITS.bytes
        || (preflight.media !== null && !validMedia(preflight.media))) return fail(500, 'internal_error', { retryable: true, uncertain: false });
    let downloaded;
    try { downloaded = await caller.downloadPrivate(PRIVATE_BUCKET, r.sourceKey, WELCOME_VIDEO_LIMITS.bytes); } catch (e) { return upstream(e); }
    if (downloaded.tooLarge) return fail(422, 'refused', { code: 'input_too_large' });
    if (!(downloaded.bytes instanceof Uint8Array) || downloaded.bytes.length !== source.bytes) return fail(422, 'refused', { code: 'source_unavailable' });
    let parsed;
    try { parsed = validateWelcomeMp4(downloaded.bytes); } catch (e) {
      if (e instanceof WelcomeVideoRejected) return fail(422, 'refused', { code: e.code });
      throw e;
    }
    const proof = { ...parsed, hash: await hashBytes(downloaded.bytes) };
    if (preflight.media !== null && !validMedia(preflight.media, proof)) return fail(409, 'restart_required');
    let staged;
    effects = true;
    try {
      staged = await caller.rpc('register_storefront_welcome_video_v1', {
        ...scope, p_content_hash: proof.hash, p_width: proof.width, p_height: proof.height, p_duration_ms: proof.durationMs, p_bytes: proof.byteLength,
      });
    } catch (e) { return upstream(e); }
    if (staged.ok !== true) return refusedRpc(staged);
    if (!exactKeys(staged, ['ok', 'entity', 'media']) || staged.entity !== ENTITY || !validMedia(staged.media, proof)
        || (preflight.media !== null && preflight.media.id !== staged.media.id)) return fail(500, 'internal_error', { retryable: true, uncertain: true });
    const media = staged.media, objectKey = media.object_key;
    const readBack = async () => {
      try {
        const got = await caller.downloadPublicAsCaller(PUBLIC_BUCKET, objectKey, WELCOME_VIDEO_LIMITS.bytes);
        if (got.tooLarge || !(got.bytes instanceof Uint8Array) || got.bytes.length !== proof.byteLength || await hashBytes(got.bytes) !== proof.hash) return fail(409, 'object_conflict');
        return null;
      } catch (e) {
        if (e instanceof UpstreamError && e.kind === 'not_found') return 'absent';
        if (e instanceof UpstreamError && e.kind === 'forbidden') return fail(409, 'restart_required');
        return upstream(e);
      }
    };
    const before = await readBack();
    if (before === 'absent') {
      try { await caller.uploadPublic(PUBLIC_BUCKET, objectKey, downloaded.bytes, 'video/mp4', 31536000); } catch (e) { return upstream(e); }
      // Both a creation and a concurrent-existing response require the actual stored bytes.
      const after = await readBack();
      if (after === 'absent') return fail(503, 'upstream_unavailable', { retryable: true, uncertain: true });
      if (after) return after;
    } else if (before) return before;
    let published;
    try {
      published = await caller.rpc('publish_storefront_welcome_video_v1', {
        p_organization_id: r.organizationId, p_restaurant_id: r.restaurantId, p_media_id: media.id, p_request_id: r.requestId,
      });
    } catch (e) { return upstream(e); }
    if (published.ok !== true) return refusedRpc(published);
    if (!exactKeys(published, ['ok', 'entity', 'media']) || published.entity !== ENTITY || !validMedia(published.media, proof, true)
        || published.media.id !== media.id || published.media.object_key !== objectKey) return fail(500, 'internal_error', { retryable: true, uncertain: true });
    return reply(200, {
      ok: true, status: 'published', kind: 'welcome_video_v1', organization_id: r.organizationId, restaurant_id: r.restaurantId, request_id: r.requestId,
      media: { id: media.id, object_key: objectKey, content_hash: proof.hash, mime_type: 'video/mp4', width: proof.width, height: proof.height,
        duration_ms: proof.durationMs, bytes: proof.byteLength, published: true, url: `/storage/v1/object/public/${PUBLIC_BUCKET}/${objectKey}` },
    });
  } catch (e) {
    const name = e instanceof Error && ['Error', 'TypeError', 'UpstreamError', 'WelcomeVideoRejected'].includes(e.name) ? e.name : 'unclassified';
    logError(`storefront-media-publish welcome video: ${name}`);
    return fail(500, 'internal_error', { retryable: true, uncertain: effects });
  }
}
