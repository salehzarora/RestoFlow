// Test double of the three Supabase services the function calls AS THE CALLER
// (GoTrue /auth/v1/user, PostgREST /rest/v1/rpc/*, Storage /storage/v1/object/*).
// The media RPCs are modelled on the migration's contract (supabase/migrations/
// 20260925100000_storefront_publish_001.sql; its real behaviour is proven by the
// pgTAP suites T-018 and zz_*): content-addressed STAGED rows, idempotency per
// (actor, client_request_id) with a key-reuse refusal, typed failures not
// claimed, finalize proving the object. Faults can be injected per step to
// simulate a request killed at any boundary, or to return a typed answer.
// Steps: an RPC name, 'download' (a PRIVATE original), 'read_public' (the
// read-back of the public content address), 'upload', '/auth/v1/user'.
import { createHash } from 'node:crypto';

const sha = (b) => createHash('sha256').update(b).digest('hex');
export const TOKEN = 'test-header.test-payload.test-signature'; // JWT-SHAPED only (3 parts); signs nothing, matches no secret pattern
export const ANON = 'test-anon-key';
export const URL_BASE = 'http://supabase.test';

export function fakeSupabase({ userId = 'user-1', canManage = true, privateObjects = new Map(), user = null } = {}) {
  const s = {
    calls: [], // {method, path, headers}
    media: new Map(), // id -> row
    objects: new Map(), // key -> {bytes, mimetype, size}
    uploads: { created: 0, exists: 0 },
    ledger: new Map(), // op:key -> {fp, result}
    faults: new Map(), // step -> 'network' | 'after_commit' | {status, body} | (state, init) => Response | null (a one-shot hook)
    // what GoTrue answers for the token (a signed-in, non-anonymous user by default)
    user: user ?? { id: userId, aud: 'authenticated', role: 'authenticated', is_anonymous: false },
    pulled: 0, // bytes the function actually pulled from a 'counted' private download
    privateObjects,
    canManage,
    seq: 0,
  };
  const json = (status, body) => new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } });
  const state = (r) => (r.published_at === null ? 'staged' : r.unpublished_at === null ? 'published' : 'retracted');

  function claimOrReplay(op, key, fp) {
    const k = `${op}:${key}`;
    if (!s.ledger.has(k)) return null;
    const l = s.ledger.get(k);
    if (l.fp !== fp) return { error: json(403, { code: '42501', message: 'management: client_request_id reused with different input' }) };
    return { replay: json(200, { ...l.result, idempotent_replay: true }) };
  }

  function stage(p) {
    if (!s.canManage) return json(200, { ok: false, error: 'permission_denied', entity: 'storefront_media' });
    const fp = JSON.stringify([p.p_organization_id, p.p_restaurant_id, p.p_source_bucket, p.p_source_key, p.p_variant, p.p_content_hash, p.p_width, p.p_height, p.p_bytes]);
    const rp = claimOrReplay('stage', p.p_client_request_id, fp);
    if (rp && rp.error) return rp.error;
    if (rp) {
      const stored = s.ledger.get(`stage:${p.p_client_request_id}`).result;
      const live = s.media.get(stored.media_id);
      if (!live) return json(200, { ok: false, error: 'stale_request', entity: 'storefront_media' });
      return json(200, { ...stored, state: state(live), idempotent_replay: true });
    }
    if (!s.privateObjects.has(`${p.p_source_bucket}/${p.p_source_key}`)) return json(200, { ok: false, error: 'source_not_found', entity: 'storefront_media' });
    const objectKey = `${'a'.repeat(32)}/${p.p_content_hash}.webp`;
    let row = [...s.media.values()].find((m) => m.object_key === objectKey);
    let result;
    if (row) {
      if (row.width !== p.p_width || row.height !== p.p_height || row.bytes !== p.p_bytes) return json(200, { ok: false, error: 'content_mismatch', entity: 'storefront_media' });
      result = { ok: true, idempotent_replay: false, entity: 'storefront_media', media_id: row.id, object_key: objectKey, state: state(row), existing: true,
        source_bucket: row.source_bucket, source_key: row.source_key, variant: row.variant,
        source_mismatch: row.source_bucket !== p.p_source_bucket || row.source_key !== p.p_source_key || row.variant !== p.p_variant };
    } else {
      row = { id: `m-${++s.seq}`, object_key: objectKey, source_bucket: p.p_source_bucket, source_key: p.p_source_key, variant: p.p_variant,
        content_hash: p.p_content_hash, width: p.p_width, height: p.p_height, bytes: p.p_bytes, published_at: null, unpublished_at: null };
      s.media.set(row.id, row);
      result = { ok: true, idempotent_replay: false, entity: 'storefront_media', media_id: row.id, object_key: objectKey, state: 'staged', existing: false,
        source_bucket: p.p_source_bucket, source_key: p.p_source_key, variant: p.p_variant, source_mismatch: false };
    }
    s.ledger.set(`stage:${p.p_client_request_id}`, { fp, result });
    return json(200, result);
  }

  function finalize(p) {
    if (!s.canManage) return json(200, { ok: false, error: 'permission_denied', entity: 'storefront_media' });
    const fp = JSON.stringify([p.p_organization_id, p.p_restaurant_id, p.p_media_id]);
    const rp = claimOrReplay('finalize', p.p_client_request_id, fp);
    if (rp && rp.error) return rp.error;
    const row = s.media.get(p.p_media_id);
    // a REPLAY re-reads its row too: a publication retracted since (or a row gone) is stale
    if (!row) return json(200, { ok: false, error: rp ? 'stale_request' : 'not_found', entity: 'storefront_media' });
    if (rp && state(row) !== 'published') return json(200, { ok: false, error: 'stale_request', entity: 'storefront_media' });
    let result;
    // the object is proven for EVERY outcome, a replay and an already-LIVE row included (as the migration does)
    const o = s.objects.get(row.object_key);
    if (!o) return json(200, { ok: false, error: 'object_missing', entity: 'storefront_media' });
    if (o.mimetype !== 'image/webp' || o.size !== row.bytes) return json(200, { ok: false, error: 'object_mismatch', entity: 'storefront_media' });
    if (rp) return rp.replay;
    if (state(row) === 'published') {
      result = { ok: true, idempotent_replay: false, entity: 'storefront_media', media_id: row.id, object_key: row.object_key, state: 'published',
        already_published: true, republished: false, replaced_media_id: null, profile_version: null };
    } else {
      const republished = row.unpublished_at !== null;
      row.published_at = 't'; row.unpublished_at = null;
      result = { ok: true, idempotent_replay: false, entity: 'storefront_media', media_id: row.id, object_key: row.object_key, state: 'published',
        already_published: false, republished, replaced_media_id: null, profile_version: null };
    }
    s.ledger.set(`finalize:${p.p_client_request_id}`, { fp, result });
    return json(200, result);
  }

  async function route(url, init) {
    const u = new URL(url);
    const headers = Object.fromEntries(Object.entries(init.headers ?? {}).map(([k, v]) => [k.toLowerCase(), v]));
    const call = { method: init.method, path: u.pathname, headers };
    s.calls.push(call);
    if (!['GET', 'POST'].includes(String(init.method).toUpperCase())) throw new Error(`test double: forbidden method ${init.method} ${u.pathname}`);
    if (headers.authorization !== `Bearer ${TOKEN}` || headers.apikey !== ANON) return json(401, { message: 'invalid token' });
    const step = u.pathname.startsWith('/rest/v1/rpc/') ? u.pathname.slice('/rest/v1/rpc/'.length)
      : u.pathname.startsWith('/storage/v1/object/authenticated/storefront-media/') ? 'read_public'
      : u.pathname.startsWith('/storage/v1/object/authenticated/') ? 'download'
        : u.pathname.startsWith('/storage/v1/object/') ? 'upload' : u.pathname;
    const fault = s.faults.get(step);
    if (fault === 'network') { s.faults.delete(step); throw new TypeError('fetch failed'); }
    if (fault && typeof fault === 'object') { s.faults.delete(step); return json(fault.status, fault.body); }
    if (typeof fault === 'function') { s.faults.delete(step); const r = fault(s, init); if (r) return r; }
    let res;
    if (u.pathname === '/auth/v1/user') res = json(200, s.user);
    else if (step === 'list_storefront_media') res = json(200, s.canManage ? { ok: true, entity: 'storefront_media', media: [] } : { ok: false, error: 'not_found', entity: 'storefront_media' });
    else if (step === 'stage_storefront_media') res = stage(JSON.parse(init.body));
    else if (step === 'finalize_storefront_media') res = finalize(JSON.parse(init.body));
    else if (step === 'download' || step === 'read_public') {
      const key = decodeURIComponent(u.pathname.slice('/storage/v1/object/authenticated/'.length));
      const [bucket, ...rest] = key.split('/');
      const objKey = rest.join('/');
      const bytes = bucket === 'storefront-media' ? s.objects.get(objKey)?.bytes : s.privateObjects.get(`${bucket}/${objKey}`);
      const shape = s.downloadShape; // undefined | 'no_length' | 'lying_length' | 'cut' | 'counted'
      const streamOf = (b, cut) => new ReadableStream({
        start(c) { const half = Math.floor(b.length / 2); c.enqueue(b.subarray(0, half)); if (cut) c.error(new TypeError('connection reset')); else { c.enqueue(b.subarray(half)); c.close(); } },
      });
      // 'counted': no length, 64 KiB per pull, pulled only when the reader asks (highWaterMark 0)
      const counted = (b) => {
        let off = 0;
        return new ReadableStream({
          pull(c) {
            if (off >= b.length) { c.close(); return; }
            const n = Math.min(65536, b.length - off);
            c.enqueue(b.slice(off, off + n)); off += n; s.pulled += n;
          },
        }, { highWaterMark: 0 });
      };
      if (bytes && shape && bucket !== 'storefront-media') {
        s.downloadShape = undefined;
        res = shape === 'counted' ? new Response(counted(bytes), { status: 200 })
          : shape === 'no_length' ? new Response(streamOf(bytes, false), { status: 200 })
          : shape === 'lying_length' ? new Response(streamOf(bytes, false), { status: 200, headers: { 'content-length': '10' } })
            : new Response(streamOf(bytes, true), { status: 200, headers: { 'content-length': String(bytes.length) } });
      } else res = bytes ? new Response(bytes, { status: 200, headers: { 'content-length': String(bytes.length) } })
        : json(400, { statusCode: '404', error: 'not_found', message: 'Object not found' });
    } else if (step === 'upload') {
      const key = decodeURIComponent(u.pathname.slice('/storage/v1/object/'.length));
      const [bucket, ...rest] = key.split('/');
      const objKey = rest.join('/');
      if (init.method !== 'POST' || bucket !== 'storefront-media') res = json(400, { statusCode: '400', error: 'unexpected' });
      else if (!([...s.media.values()].some((m) => m.object_key === objKey))) res = json(400, { statusCode: '403', error: 'Unauthorized', message: 'new row violates row-level security policy' });
      else if (s.objects.has(objKey)) { s.uploads.exists++; res = json(400, { statusCode: '409', error: 'Duplicate', message: 'The resource already exists' }); }
      else {
        const bytes = new Uint8Array(init.body);
        s.objects.set(objKey, { bytes, mimetype: headers['content-type'], size: bytes.length, cacheControl: headers['cache-control'], upsert: headers['x-upsert'] });
        s.uploads.created++;
        res = json(200, { Key: `storefront-media/${objKey}` });
      }
    } else res = json(404, { message: 'no route' });
    if (fault === 'after_commit') { s.faults.delete(step); throw new TypeError('connection reset after the server committed'); }
    return res;
  }

  s.fetchImpl = async (url, init = {}) => route(url, init);
  s.sha = sha;
  return s;
}
