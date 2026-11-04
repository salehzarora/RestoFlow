// CI transport only. The application's production origin admission rule is
// unchanged. No response, payload, credential or application state is invented.
export const LOGICAL_ORIGIN = 'https://oqmevrndtivqxgyvcmwy.supabase.co';
export const LOCAL_API = 'http://127.0.0.1:54321';
const mediaPath = /^\/storage\/v1\/object\/public\/storefront-media\/[0-9a-f]{32}\/[0-9a-f]{64}\.webp$/;
const deny = () => { throw new Error('cinematic_transport_denied'); };

function exactUrl(value, origin) {
  let u; try { u = new URL(value); } catch { return deny(); }
  if (u.origin !== origin || u.username || u.password || u.search || u.hash || value !== u.href) deny();
  return u;
}
export function localMediaTarget(value, method = 'GET') {
  const u = exactUrl(value, LOGICAL_ORIGIN);
  if (method !== 'GET' || !mediaPath.test(u.pathname)) deny();
  return LOCAL_API + u.pathname;
}
export function logicalMediaUrl(value) {
  const u = exactUrl(value, LOCAL_API);
  if (!mediaPath.test(u.pathname)) deny();
  return LOGICAL_ORIGIN + u.pathname;
}
export function createMenuTransport(nativeFetch, { anonKey, slug }, evidence = { mappedReads: 0, rejectedReads: 0 }) {
  if (typeof anonKey !== 'string' || !/^cinematic-[a-z0-9-]+$/.test(slug)) deny();
  const claims = (() => { try { return JSON.parse(Buffer.from(anonKey.split('.')[1], 'base64url').toString()); } catch { return null; } })();
  if (anonKey.split('.').length !== 3 || claims?.role !== 'anon') deny();
  return async (input, init) => {
    let text, headers, signal;
    try {
      const u = exactUrl(typeof input === 'string' ? input : input instanceof URL ? input.href : input.url, LOGICAL_ORIGIN);
      const method = init?.method ?? input?.method ?? 'GET';
      headers = new Headers(init?.headers ?? input?.headers);
      text = typeof init?.body === 'string' ? init.body : input instanceof Request ? await input.clone().text() : '';
      signal = init?.signal ?? input?.signal;
      if (u.pathname !== '/rest/v1/rpc/storefront_menu_v5' || method !== 'POST' ||
          JSON.stringify([...headers.keys()].sort()) !== JSON.stringify(['accept', 'apikey', 'authorization', 'content-type']) ||
          headers.get('accept') !== 'application/json' || headers.get('content-type') !== 'application/json' ||
          headers.get('apikey') !== anonKey || headers.get('authorization') !== `Bearer ${anonKey}` ||
          text !== JSON.stringify({ p_slug: slug }) || (init?.redirect && init.redirect !== 'error')) deny();
    } catch { evidence.rejectedReads++; return deny(); }
    evidence.mappedReads++;
    // Pass the untouched request body and local anon headers to real PostgREST.
    // Return its Response directly: status, headers and body are not rewritten.
    // No fallback can pass the logical hosted URL to native fetch.
    return nativeFetch(`${LOCAL_API}/rest/v1/rpc/storefront_menu_v5`, {
      method: 'POST', headers, body: text, signal, redirect: 'error',
    });
  };
}
