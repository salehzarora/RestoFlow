// STOREFRONT-PUBLISH-001: the CALLER-CONTEXT Supabase client of the media function.
//
// Every request this module makes carries the CALLER's own access token
// (`Authorization: Bearer <user JWT>`) plus the project's publishable/anon key
// (`apikey`), so Auth, PostgREST and Storage evaluate it exactly as they would a
// request from the signed-in Dashboard user: the database sees the user
// (auth.uid() -> app.current_app_user_id()), RLS and the RPC authority checks
// apply unchanged. There is no privileged key of any kind here: the function is
// configured with the project URL and the public anon key only.
//
// Dependency-free on purpose (plain fetch): no npm / jsr client library, so no
// floating semver range and nothing fetched at runtime. Host-agnostic (Deno
// edge runtime and Node tests inject `fetchImpl`).

/** Upstream call outcome classes the handler maps to HTTP statuses. */
export class UpstreamError extends Error {
  constructor(kind, { status = null, code = null } = {}) {
    super(`${kind}${status !== null ? ` ${status}` : ''}${code ? ` ${code}` : ''}`);
    this.kind = kind; // 'unavailable' (network / timeout / 5xx) | 'unauthenticated' | 'forbidden' | 'not_found' | 'rejected'
    this.status = status;
    this.code = code;
  }
}

/**
 * Percent-encodes an object key segment by segment. Defence in depth (review SEC-4):
 * an empty, '.' or '..' segment is refused outright, so no key can ever be
 * normalised into another path by a proxy or the Storage router (the request
 * validator and the stage RPC's key grammar already make such keys unreachable).
 */
export function encodeKey(key) {
  if (typeof key !== 'string' || key.length === 0) throw new TypeError('storage key: not a non-empty string');
  return key.split('/').map((segment) => {
    if (segment === '' || segment === '.' || segment === '..') throw new TypeError('storage key: empty or dot segment');
    return encodeURIComponent(segment);
  }).join('/');
}

/**
 * Review SEC-1: the principal GoTrue answered for must be a signed-in, NON-anonymous
 * user of role and audience `authenticated`. A paired device's or a kiosk's anonymous
 * session, or any other role / audience, is refused before any RPC or download.
 */
export function isPublisherPrincipal(user) {
  return user !== null && typeof user === 'object'
    && user.is_anonymous !== true
    && user.role === 'authenticated'
    && user.aud === 'authenticated';
}

/**
 * Reads a response body with a hard byte cap, streaming, so an unexpectedly
 * large object can never be buffered whole. Returns Uint8Array, or null when the
 * cap is exceeded (the stream is cancelled).
 */
export async function readCapped(body, contentLength, maxBytes) {
  if (contentLength !== null && /^[0-9]+$/.test(contentLength) && Number(contentLength) > maxBytes) {
    try { await body?.cancel(); } catch { /* ignore */ }
    return null;
  }
  if (!body) return new Uint8Array(0);
  const reader = body.getReader();
  const chunks = [];
  let total = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.byteLength;
    if (total > maxBytes) {
      try { await reader.cancel(); } catch { /* ignore */ }
      return null;
    }
    chunks.push(value);
  }
  const out = new Uint8Array(total);
  let o = 0;
  for (const c of chunks) { out.set(c, o); o += c.byteLength; }
  return out;
}

/**
 * @param {{ supabaseUrl: string, anonKey: string, accessToken: string,
 *           fetchImpl?: typeof fetch, timeoutMs?: number }} options
 */
export function createCallerClient({ supabaseUrl, anonKey, accessToken, fetchImpl = fetch, timeoutMs = 15000 }) {
  const base = supabaseUrl.replace(/\/+$/, '');
  const headers = (extra = {}) => ({ authorization: `Bearer ${accessToken}`, apikey: anonKey, ...extra });

  async function call(url, init) {
    try {
      return await fetchImpl(url, { ...init, signal: AbortSignal.timeout(timeoutMs) });
    } catch {
      throw new UpstreamError('unavailable'); // network error or timeout: outcome unknown
    }
  }
  async function jsonOf(res) {
    try { return await res.json(); } catch { return null; }
  }

  return {
    /** The signed-in user behind the token (GoTrue verifies signature and expiry). */
    async getUser() {
      const res = await call(`${base}/auth/v1/user`, { method: 'GET', headers: headers() });
      if (res.status === 200) {
        const user = await jsonOf(res);
        if (user && typeof user.id === 'string' && user.id.length > 0) return user;
        throw new UpstreamError('unauthenticated', { status: 200 });
      }
      await res.body?.cancel();
      if (res.status === 401 || res.status === 403 || res.status === 400 || res.status === 404) throw new UpstreamError('unauthenticated', { status: res.status });
      throw new UpstreamError('unavailable', { status: res.status });
    },

    /**
     * A PostgREST RPC as the caller. Resolves to the JSON envelope on 200;
     * raised Postgres errors surface as UpstreamError with the SQLSTATE code.
     */
    async rpc(fn, params) {
      const res = await call(`${base}/rest/v1/rpc/${fn}`, {
        method: 'POST',
        headers: headers({ 'content-type': 'application/json', accept: 'application/json' }),
        body: JSON.stringify(params),
      });
      const body = await jsonOf(res);
      if (res.status === 200) {
        if (body === null || typeof body !== 'object' || Array.isArray(body)) throw new UpstreamError('unavailable', { status: 200, code: 'bad_envelope' });
        return body;
      }
      const code = body && typeof body.code === 'string' ? body.code : null;
      const message = body && typeof body.message === 'string' ? body.message : '';
      if (res.status === 401) throw new UpstreamError('unauthenticated', { status: 401, code });
      if (code === '42501') {
        // the management ledger's key-reuse refusal is a distinct, recoverable outcome
        if (/reused with different input/.test(message)) throw new UpstreamError('rejected', { status: res.status, code: 'request_id_reused' });
        throw new UpstreamError('forbidden', { status: res.status, code });
      }
      if (res.status === 403) throw new UpstreamError('forbidden', { status: 403, code });
      if (res.status >= 500 || res.status === 429 || res.status === 408) throw new UpstreamError('unavailable', { status: res.status, code });
      throw new UpstreamError('rejected', { status: res.status, code });
    },

    /** Streams a private object the CALLER may read (the bucket's own read policy applies). */
    async downloadPrivate(bucket, key, maxBytes) {
      const res = await call(`${base}/storage/v1/object/authenticated/${encodeURIComponent(bucket)}/${encodeKey(key)}`, { method: 'GET', headers: headers() });
      if (res.status === 200) {
        let bytes;
        try {
          bytes = await readCapped(res.body, res.headers.get('content-length'), maxBytes);
        } catch {
          throw new UpstreamError('unavailable', { status: 200, code: 'body_interrupted' }); // cut mid-body: outcome unknown
        }
        return bytes === null ? { tooLarge: true } : { bytes };
      }
      // Storage answers most errors with HTTP 400 and the real class in the JSON body
      // ({statusCode, error, message}): classify by the body, not the HTTP status alone.
      const body = await jsonOf(res);
      const statusCode = body && body.statusCode !== undefined ? String(body.statusCode) : String(res.status);
      const text = `${body && typeof body.error === 'string' ? body.error : ''} ${body && typeof body.message === 'string' ? body.message : ''}`;
      if (res.status >= 500 || res.status === 429 || res.status === 408 || /^5/.test(statusCode)) throw new UpstreamError('unavailable', { status: res.status, code: statusCode });
      if (res.status === 401 || statusCode === '401' || /jwt|token|signature/i.test(text)) throw new UpstreamError('unauthenticated', { status: res.status, code: statusCode });
      if (statusCode === '403') throw new UpstreamError('forbidden', { status: res.status, code: statusCode });
      // "Object not found" answers both a missing object and one the caller may not read (the
      // SELECT policy hides it): the same outcome to the caller.
      throw new UpstreamError('not_found', { status: res.status, code: statusCode });
    },

    /**
     * Uploads the derivative to the PUBLIC bucket as the caller, never overwriting
     * (x-upsert: false): the storage INSERT policy admits only a REGISTERED key of a
     * restaurant the caller manages. Resolves 'created' | 'exists'.
     */
    async uploadPublic(bucket, key, bytes, contentType, cacheControlSeconds) {
      const res = await call(`${base}/storage/v1/object/${encodeURIComponent(bucket)}/${encodeKey(key)}`, {
        method: 'POST',
        headers: headers({ 'content-type': contentType, 'x-upsert': 'false', 'cache-control': `max-age=${cacheControlSeconds}` }),
        body: bytes,
      });
      const body = await jsonOf(res);
      if (res.status === 200 || res.status === 201) return 'created';
      const statusCode = body && body.statusCode !== undefined ? String(body.statusCode) : null;
      if (res.status === 409 || statusCode === '409' || (body && body.error === 'Duplicate')) return 'exists';
      if (res.status === 401) throw new UpstreamError('unauthenticated', { status: 401 });
      if (res.status === 403 || statusCode === '403') throw new UpstreamError('forbidden', { status: res.status });
      if (res.status >= 500 || res.status === 429 || res.status === 408) throw new UpstreamError('unavailable', { status: res.status });
      throw new UpstreamError('rejected', { status: res.status, code: statusCode });
    },

    /** Reads back an object of the public bucket through the caller's (registered-key) read policy. */
    async downloadPublicAsCaller(bucket, key, maxBytes) {
      return this.downloadPrivate(bucket, key, maxBytes);
    },
  };
}
