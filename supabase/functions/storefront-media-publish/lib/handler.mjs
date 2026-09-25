// STOREFRONT-PUBLISH-001: the request workflow of `storefront-media-publish`.
//
// One POST publishes ONE ladder rung of ONE logo / hero derivative, entirely as the
// CALLER (their JWT on every upstream request; no privileged key exists here):
//
//   body cap (a top-level key named twice is refused) -> authenticate (GoTrue; only
//   a signed-in, non-anonymous 'authenticated' user) -> validate every field (exact allowlists)
//   -> authority preflight (list_storefront_media: manager+ or nothing is read)
//   -> download the PRIVATE original (streamed, capped at its bucket limit)
//   -> derive ONE rung with the pinned recipe c4 (202 ladder_next when over the cap)
//   -> stage (idempotent) -> upload the derivative to the PUBLIC bucket
//   (x-upsert false; an existing object must hash to the same content address)
//   -> finalize (idempotent; proves the object) -> 200.
//
// Recovery model (owner reliability amendment): the hosted runtime may terminate a
// request abruptly (CPU / wall / memory limits, platform restarts) without a typed
// error. Every step is therefore idempotent and durable instead:
//   - stage and finalize use keys derived from the caller's ONE request_id, so a
//     retry replays them (ids.mjs); typed DB failures are never claimed;
//   - the object name is the sha-256 of the deterministic derivative, so a retried
//     upload finds the same object (compare, never overwrite, never delete);
//   - nothing public REFERENCES a derivative until finalize proves the object and
//     the profile writer points a slot at the LIVE row, so a killed request leaves
//     at most a STAGED row and/or an unreferenced object (recoverable: retry the
//     same request, or cancel the row from the Dashboard). An uploaded object is
//     fetchable by anyone holding its URL from the moment of upload (the bucket is
//     public; its name is a content address, not a secret);
//   - after ANY unknown outcome the Dashboard re-reads list_storefront_media and
//     the profile (authoritative state) and may retry with the same request_id.
// No storefront-media object is ever deleted by this function.

import { DerivationError, RECIPE } from './recipe.mjs';
import { SourceRejected } from './sniff.mjs';
import { hasDuplicateTopLevelKey, validateRequest } from './validate.mjs';
import { createCallerClient, isPublisherPrincipal, readCapped, UpstreamError } from './caller.mjs';
import { derivedRequestId } from './ids.mjs';

export const MAX_BODY_BYTES = 4096;
const MAX_TOKEN_CHARS = 8192;
const PUBLIC_BUCKET = 'storefront-media';
const OBJECT_CACHE_SECONDS = 31536000; // content-addressed: on this path the bytes behind a name never change (Q-033)
// public.storefront_media.object_key's own CHECK grammar (READ-001 migration)
const OBJECT_KEY_RE = /^[0-9a-f]{32}\/[0-9a-f]{64}\.webp$/;

const CORS = Object.freeze({
  'access-control-allow-origin': '*',
  'access-control-allow-headers': 'authorization, x-client-info, apikey, content-type',
  'access-control-allow-methods': 'POST, OPTIONS',
  'access-control-max-age': '600',
});

function reply(status, body) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store', ...CORS },
  });
}
const fail = (status, statusText, extra = {}) => reply(status, { ok: false, status: statusText, ...extra });

const sha256Hex = async (bytes) =>
  Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', bytes)), (b) => b.toString(16).padStart(2, '0')).join('');

/** Maps an upstream failure at a given step to the typed response. */
function upstreamFailure(e, uncertain) {
  if (!(e instanceof UpstreamError)) throw e;
  switch (e.kind) {
    case 'unauthenticated': return fail(401, 'unauthenticated');
    case 'forbidden': return fail(403, 'permission_denied');
    case 'not_found': return fail(404, 'source_not_found');
    case 'rejected':
      if (e.code === 'request_id_reused') return fail(409, 'restart_required');
      return fail(500, 'internal_error', { retryable: true, uncertain });
    default: return fail(503, 'upstream_unavailable', { retryable: true, uncertain });
  }
}

/**
 * @param {{ supabaseUrl: string, anonKey: string, engine: () => Promise<any>,
 *           retireWorker: () => void, fetchImpl?: typeof fetch, upstreamTimeoutMs?: number,
 *           logError?: (msg: string) => void }} deps
 */
export function createHandler({ supabaseUrl, anonKey, engine, retireWorker, fetchImpl = fetch, upstreamTimeoutMs = 15000, logError = () => {} }) {
  let poisoned = false;

  return async function handle(req) {
    // A per-request marker of how far the SERVER-SIDE effects went, for `uncertain`.
    let effects = false;
    try {
      if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: { ...CORS } });
      if (req.method !== 'POST') return fail(405, 'method_not_allowed');
      if (!supabaseUrl || !anonKey) return fail(500, 'internal_error', { code: 'function_misconfigured', retryable: false, uncertain: false });
      if (poisoned) {
        retireWorker();
        return fail(503, 'engine_unavailable', { retryable: true });
      }
      const contentType = (req.headers.get('content-type') ?? '').toLowerCase();
      if (!/^application\/json(\s*;|$)/.test(contentType)) return fail(415, 'unsupported_media_type');

      // (1) bounded body, read BEFORE anything else touches it
      const raw = await readCapped(req.body, req.headers.get('content-length'), MAX_BODY_BYTES);
      if (raw === null) return fail(413, 'request_too_large');
      let body, text;
      try {
        text = new TextDecoder('utf-8', { fatal: true }).decode(raw);
        body = JSON.parse(text);
      } catch {
        return fail(400, 'invalid_request', { field: 'body', reason: 'json' });
      }
      // a key named twice is ambiguous (JSON.parse keeps the last): refused, never guessed
      if (hasDuplicateTopLevelKey(text)) return fail(400, 'invalid_request', { field: 'body', reason: 'duplicate_key' });

      // (2) authenticate: a bearer user token, verified by GoTrue (signature, expiry, revocation)
      const auth = req.headers.get('authorization') ?? '';
      const m = /^Bearer ([A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+)$/.exec(auth);
      if (!m || m[1].length > MAX_TOKEN_CHARS) return fail(401, 'unauthenticated');
      const caller = createCallerClient({ supabaseUrl, anonKey, accessToken: m[1], fetchImpl, timeoutMs: upstreamTimeoutMs });
      let user;
      try {
        user = await caller.getUser();
      } catch (e) {
        return upstreamFailure(e, false);
      }
      // SEC-1: an anonymous (paired device / kiosk) session, or any role / audience other
      // than 'authenticated', is refused here, before any RPC or download
      if (!isPublisherPrincipal(user)) return fail(401, 'unauthenticated');

      // (3) validate every field before any object lookup
      const v = validateRequest(body);
      if (!v.ok) return fail(400, 'invalid_request', { field: v.field, reason: v.reason });
      const r = v.value;

      // (4) authority preflight: a caller who cannot manage this restaurant's storefront
      //     never makes the function download or decode anything
      try {
        const listing = await caller.rpc('list_storefront_media', { p_organization_id: r.organizationId, p_restaurant_id: r.restaurantId });
        if (listing.ok !== true) return fail(403, 'permission_denied');
      } catch (e) {
        return upstreamFailure(e, false);
      }

      // (5) the PRIVATE original, as the caller, never buffered beyond its bucket cap
      let source;
      try {
        source = await caller.downloadPrivate(r.sourceBucket, r.sourceKey, r.sourceMaxBytes);
      } catch (e) {
        return upstreamFailure(e, false);
      }
      if (source.tooLarge) return fail(422, 'refused', { code: 'input_too_large' });

      // (6) one ladder rung of the canonical recipe
      let deriver;
      try {
        deriver = await engine();
      } catch {
        poisoned = true;
        retireWorker();
        return fail(503, 'engine_unavailable', { retryable: true });
      }
      let d;
      try {
        d = await deriver.derive(source.bytes, { variant: r.variant, source: r.sourceBucket, rung: r.rung });
      } catch (e) {
        if (e instanceof DerivationError && e.code === 'engine_unavailable') {
          poisoned = true;
          retireWorker();
          return fail(503, 'engine_unavailable', { retryable: true });
        }
        if (e instanceof SourceRejected || e instanceof DerivationError) {
          // the source's typed refusal stands; a codec failure that left the engine untrusted
          // (a one-per-worker wasm instance threw) also retires this worker
          if (deriver.poisoned === true) {
            poisoned = true;
            retireWorker();
          }
          return fail(422, 'refused', { code: e.code });
        }
        throw e;
      }
      source = null; // the private bytes are no longer needed (never logged, never returned)
      if (d.status === 'ladder_next') return reply(202, { ok: false, status: 'ladder_next', next_rung: d.nextRung });

      // Independent re-check of what is about to become public (belt and braces over the recipe).
      if (d.status !== 'derived' || d.rung !== r.rung
          || !(d.bytes instanceof Uint8Array) || d.bytes.length !== d.byteLength || d.byteLength > RECIPE.maxOutputBytes
          || !Number.isInteger(d.width) || !Number.isInteger(d.height) || d.width < 1 || d.height < 1
          || Math.max(d.width, d.height) > r.variantWidth || typeof d.sha256 !== 'string' || (await sha256Hex(d.bytes)) !== d.sha256) {
        return fail(422, 'refused', { code: 'self_check_failed' });
      }

      // (7) stage (idempotent under the derived key)
      const stageId = await derivedRequestId(r.requestId, 'stage');
      const finalizeId = await derivedRequestId(r.requestId, 'finalize');
      let staged;
      effects = true;
      try {
        staged = await caller.rpc('stage_storefront_media', {
          p_client_request_id: stageId, p_organization_id: r.organizationId, p_restaurant_id: r.restaurantId,
          p_source_bucket: r.sourceBucket, p_source_key: r.sourceKey, p_variant: r.variant,
          p_content_hash: d.sha256, p_width: d.width, p_height: d.height, p_bytes: d.byteLength,
        });
      } catch (e) {
        return upstreamFailure(e, true);
      }
      if (staged.ok !== true) return stageRefusal(staged);
      const objectKey = staged.object_key;
      // the registered key must be exactly <restaurant prefix>/<this content address>.webp
      if (typeof objectKey !== 'string' || !OBJECT_KEY_RE.test(objectKey) || objectKey.slice(33, 97) !== d.sha256 || typeof staged.media_id !== 'string'
          || typeof staged.source_bucket !== 'string' || typeof staged.source_key !== 'string' || typeof staged.variant !== 'string') {
        return fail(500, 'internal_error', { retryable: true, uncertain: true });
      }

      // (8) the derivative into the PUBLIC bucket, as the caller, never overwriting. Done for
      //     EVERY state, a LIVE row included: the content address is read first (through the
      //     caller's registered-key read policy); an existing object must be exactly these bytes,
      //     a missing one is (re-)created with x-upsert false. A retried request therefore never
      //     re-sends the bytes of an object that is already there.
      const readBack = async () => {
        try {
          const got = await caller.downloadPublicAsCaller(PUBLIC_BUCKET, objectKey, RECIPE.maxOutputBytes);
          if (got.tooLarge || (await sha256Hex(got.bytes)) !== d.sha256) return fail(409, 'object_conflict');
          return null; // the right bytes are in place
        } catch (e) {
          if (!(e instanceof UpstreamError)) throw e;
          if (e.kind === 'not_found') return 'absent';
          if (e.kind === 'unauthenticated') return fail(401, 'unauthenticated');
          // the key was just registered and the preflight proved the rank: a refused read means the
          // registration is gone (its STAGED row was cancelled meanwhile) -> a new logical request
          if (e.kind === 'forbidden') return fail(409, 'restart_required');
          return fail(503, 'upstream_unavailable', { retryable: true, uncertain: true });
        }
      };
      const first = await readBack();
      if (first === 'absent') {
        let put;
        try {
          put = await caller.uploadPublic(PUBLIC_BUCKET, objectKey, d.bytes, 'image/webp', OBJECT_CACHE_SECONDS);
        } catch (e) {
          // a refused INSERT after a successful stage: the registration is gone -> restart
          if (e instanceof UpstreamError && e.kind === 'forbidden') return fail(409, 'restart_required');
          return upstreamFailure(e, true);
        }
        if (put === 'exists') {
          // a concurrent request of the same bytes won the race: compare, never overwrite
          const second = await readBack();
          if (second === 'absent') return fail(503, 'upstream_unavailable', { retryable: true, uncertain: true });
          if (second) return second;
        }
      } else if (first) {
        return first;
      }

      // (9) finalize: the server proves the object and publishes (idempotent under the derived key)
      let fin;
      try {
        fin = await caller.rpc('finalize_storefront_media', {
          p_client_request_id: finalizeId, p_organization_id: r.organizationId, p_restaurant_id: r.restaurantId,
          p_media_id: staged.media_id,
        });
      } catch (e) {
        return upstreamFailure(e, true);
      }
      if (fin.ok !== true) {
        switch (fin.error) {
          case 'permission_denied': return fail(403, 'permission_denied');
          case 'not_found': return fail(409, 'restart_required'); // the staged row was cancelled meanwhile
          case 'stale_request': return fail(409, 'restart_required'); // a replayed publication was retracted since
          case 'object_mismatch': return fail(409, 'object_conflict');
          case 'object_missing': return fail(503, 'upstream_unavailable', { retryable: true, uncertain: true });
          default: return fail(500, 'internal_error', { retryable: true, uncertain: true });
        }
      }
      return reply(200, {
        ok: true,
        status: 'published',
        recipe: RECIPE.id,
        rung: d.rung,
        idempotent_replay: fin.idempotent_replay === true,
        already_published: fin.already_published === true,
        republished: fin.republished === true,
        replaced_media_id: typeof fin.replaced_media_id === 'string' ? fin.replaced_media_id : null,
        profile_version: Number.isInteger(fin.profile_version) ? fin.profile_version : null,
        // true when the bytes were already registered for ANOTHER source / variant: `media`
        // then describes that existing row (identical bytes), not the requested source
        source_mismatch: staged.source_mismatch === true,
        media: {
          id: staged.media_id, object_key: objectKey, content_hash: d.sha256,
          width: d.width, height: d.height, bytes: d.byteLength,
          variant: staged.variant, source_bucket: staged.source_bucket, source_key: staged.source_key,
          state: 'published',
        },
      });
    } catch (e) {
      // Never echo request data; the error name and a typed code only.
      logError(`storefront-media-publish internal_error: ${e && e.name ? e.name : 'Error'}`);
      return fail(500, 'internal_error', { retryable: true, uncertain: effects });
    }
  };
}

function stageRefusal(staged) {
  switch (staged.error) {
    case 'permission_denied': return fail(403, 'permission_denied');
    case 'source_not_found': return fail(404, 'source_not_found');
    case 'content_mismatch': return fail(409, 'object_conflict');
    // the replayed stage names a row that was cancelled since: start a NEW logical request
    case 'stale_request': return fail(409, 'restart_required');
    case 'invalid': return fail(422, 'refused', { code: typeof staged.reason === 'string' ? staged.reason : 'invalid' });
    default: return fail(500, 'internal_error', { retryable: true, uncertain: true });
  }
}
