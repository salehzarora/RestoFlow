// BIZBOT-STOREFRONT-CINEMATIC-001B: real-service helpers, never a mocked actor.
import assert from 'node:assert/strict';
import { readFileSync, statSync } from 'node:fs';
import { isAbsolute, relative, resolve } from 'node:path';

export const API_URL = 'http://127.0.0.1:54321';
export const DASHBOARD_URL = 'http://127.0.0.1:57026';
export const STOREFRONT_URL = 'http://127.0.0.1:3000';

export function assertEphemeralEnvironment(env = process.env) {
  assert.equal(env.GITHUB_ACTIONS, 'true', 'Run only on the authorized ephemeral Actions runner');
  assert.equal(env.CI, 'true');
  assert.equal(env.CINEMATIC_EPHEMERAL, 'BIZBOT-STOREFRONT-CINEMATIC-001B');
  for (const key of ['SUPABASE_ACCESS_TOKEN', 'SUPABASE_SERVICE_ROLE_KEY', 'SUPABASE_DB_PASSWORD']) {
    assert.ok(!env[key], `Hosted/privileged environment input is forbidden: ${key}`);
  }
}

export function assertLocalUrl(value, origin = API_URL) {
  const url = new URL(value);
  assert.equal(url.origin, origin, 'Only the fixed ephemeral loopback endpoint is allowed');
  assert.equal(url.username, '');
  assert.equal(url.password, '');
  assert.equal(url.hash, '');
  return url;
}

export function assertAnonKey(key) {
  assert.equal(typeof key, 'string');
  const parts = key.split('.');
  assert.equal(parts.length, 3, 'Use the local CLI anon JWT, never a service-role key');
  const claims = JSON.parse(Buffer.from(parts[1], 'base64url').toString('utf8'));
  assert.equal(claims.role, 'anon', 'Only the local anon client key is allowed');
  return key;
}

export function fixturePath(env = process.env) {
  const path = env.CINEMATIC_FIXTURE_FILE;
  assert.ok(path && isAbsolute(path), 'CINEMATIC_FIXTURE_FILE must be an absolute private path');
  const workspace = resolve(env.GITHUB_WORKSPACE || process.cwd());
  const within = relative(workspace, resolve(path));
  assert.ok(within.startsWith('..') && !isAbsolute(within), 'Credentials must stay outside the checkout/artifacts');
  return path;
}

export function readFixture() {
  assertEphemeralEnvironment();
  const path = fixturePath();
  assert.equal(statSync(path).mode & 0o077, 0, 'Fixture credentials must be private');
  const fixture = JSON.parse(readFileSync(path, 'utf8'));
  assert.equal(fixture.apiUrl, API_URL);
  assertAnonKey(fixture.anonKey);
  return fixture;
}

// Redirects are rejected before another endpoint can receive a token. Callers
// receive status/data, not a Response whose diagnostic may expose headers.
export async function request(fixture, token, path, { method = 'GET', body, bytes, contentType, timeoutMs = 60_000 } = {}) {
  assert.equal(fixture.apiUrl, API_URL);
  assertAnonKey(fixture.anonKey);
  assert.ok(path.startsWith('/') && !path.startsWith('//'));
  const url = assertLocalUrl(new URL(path, API_URL).href);
  assert.ok(Number.isInteger(timeoutMs) && timeoutMs > 0 && timeoutMs <= 60_000, 'Bounded local request timeout required');
  const headers = { apikey: fixture.anonKey };
  if (token) headers.authorization = `Bearer ${token}`;
  if (body !== undefined) headers['content-type'] = 'application/json';
  if (contentType) headers['content-type'] = contentType;
  let response;
  try {
    response = await fetch(url, {
      method, headers, body: bytes ?? (body === undefined ? undefined : JSON.stringify(body)),
      redirect: 'error', signal: AbortSignal.timeout(timeoutMs),
    });
  } catch {
    throw new Error(`Local ${method} request failed without a response`);
  }
  const dataBytes = Buffer.from(await response.arrayBuffer());
  let data = null;
  if ((response.headers.get('content-type') || '').includes('json')) {
    try { data = JSON.parse(dataBytes.toString('utf8')); } catch { /* invalid envelope fails caller assertions */ }
  }
  return { status: response.status, ok: response.ok, data, bytes: dataBytes,
    contentType: response.headers.get('content-type'), runtimeCode: response.headers.get('sb-error-code') };
}

export async function ownerSession(fixture, principal) {
  const result = await request(fixture, null, '/auth/v1/token?grant_type=password', {
    method: 'POST', body: { email: principal.email, password: principal.password },
  });
  assert.equal(result.status, 200, 'Real password sign-in must succeed');
  const token = result.data?.access_token;
  assert.equal(typeof token, 'string', 'GoTrue must issue the user session');
  const user = await request(fixture, token, '/auth/v1/user');
  assert.equal(user.status, 200);
  assert.equal(user.data?.id, principal.authUserId, 'Session identity must match the real fixture principal');
  assert.notEqual(user.data?.is_anonymous, true);
  assert.equal(user.data?.role, 'authenticated');
  return token;
}

export function scope(owner) {
  return { p_organization_id: owner.orgId, p_restaurant_id: owner.restaurantId };
}

export async function rpc(fixture, token, name, args) {
  assert.match(name, /^[a-z][a-z0-9_]+$/);
  return request(fixture, token, `/rest/v1/rpc/${name}`, { method: 'POST', body: args });
}

export async function readContent(fixture, token, owner = fixture.ownerA) {
  const result = await rpc(fixture, token, 'get_restaurant_storefront_content_v3', scope(owner));
  assert.equal(result.status, 200, 'Authorized content read must succeed');
  assert.equal(result.data?.ok, true);
  return result.data;
}

export async function readInvariants(fixture, token, owner = fixture.ownerA) {
  const profile = await rpc(fixture, token, 'get_restaurant_storefront_profile', scope(owner));
  const receipt = await rpc(fixture, token, 'get_restaurant_receipt_logo', scope(owner));
  assert.equal(profile.status, 200);
  assert.equal(profile.data?.ok, true);
  assert.equal(receipt.status, 200);
  assert.equal(receipt.data?.ok, true);
  return {
    heroMediaId: profile.data.profile.hero_media_id,
    logoMediaId: profile.data.profile.logo_media_id,
    receiptLogoKey: receipt.data.receipt_logo_path,
    receiptLogoEnabled: receipt.data.receipt_logo_enabled,
    receiptLogoVersion: receipt.data.receipt_logo_version,
  };
}

export function storagePath(key) {
  return key.split('/').map(encodeURIComponent).join('/');
}

export function assertDenied(result, label) {
  const data = result.data;
  assert.ok(!String(data?.code || '').startsWith('PGRST'), `${label}: PostgREST routing/schema/auth infrastructure failure is not a permission result`);
  if (result.status === 200) {
    assert.equal(data?.ok, false, `${label}: successful private envelope is forbidden`);
    assert.ok(['not_found', 'permission_denied'].includes(data.error), `${label}: expected an authorization refusal`);
    assert.deepEqual(Object.keys(data).sort(), ['entity', 'error', 'ok'], `${label}: refusal must not leak private state`);
    return;
  }
  assert.ok([400, 401, 403, 404].includes(result.status), `${label}: expected denial, not an infrastructure error`);
  if (result.status === 400) {
    assert.ok(['401', '403', '404'].includes(String(data?.statusCode)) || data?.code === '42501', `${label}: HTTP 400 must carry an authorization/not-found code`);
  }
}

export function assertRpcDenied(result, label) {
  assertDenied(result, label);
  if (result.status !== 200) {
    assert.equal(result.status, 403, `${label}: real authenticated RPC requires a typed permission refusal`);
    assert.equal(result.data?.code, '42501', `${label}: missing routes and infrastructure errors are not denials`);
  }
}
