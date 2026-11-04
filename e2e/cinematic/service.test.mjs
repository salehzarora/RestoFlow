// Local unit checks for the integration harness boundary; not Auth evidence.
import test from 'node:test';
import assert from 'node:assert/strict';
import { API_URL, assertLocalUrl, assertAnonKey, assertDenied, assertRpcDenied, assertEphemeralEnvironment, fixturePath } from './service.mjs';

test('network boundary allows only the fixed loopback service and rejects credentials/fragments', () => {
  assert.equal(assertLocalUrl(`${API_URL}/auth/v1/user`).origin, API_URL);
  for (const url of ['https://example.supabase.co/auth/v1/user', 'http://localhost:54321/',
    'http://127.0.0.1:3000/', 'https://127.0.0.1:54321/', 'http://user:pass@127.0.0.1:54321/',
    'http://127.0.0.1:54321/#secret', 'http://127.0.0.1.example.test:54321/']) {
    assert.throws(() => assertLocalUrl(url));
  }
});

test('only anon client keys accepted, never service_role or an Auth user key', () => {
  const key = (role) => `e30.${Buffer.from(JSON.stringify({ role })).toString('base64url')}.synthetic`;
  assert.equal(assertAnonKey(key('anon')), key('anon'));
  for (const role of ['service_role', 'authenticated', undefined]) assert.throws(() => assertAnonKey(key(role)));
  assert.throws(() => assertAnonKey('not-a-key'));
});

test('runner opt-in is explicit and rejects hosted or privileged env input', () => {
  const env = { GITHUB_ACTIONS: 'true', CI: 'true', CINEMATIC_EPHEMERAL: 'BIZBOT-STOREFRONT-CINEMATIC-001B' };
  assert.doesNotThrow(() => assertEphemeralEnvironment(env));
  for (const key of Object.keys(env)) assert.throws(() => assertEphemeralEnvironment({ ...env, [key]: '' }));
  for (const key of ['SUPABASE_ACCESS_TOKEN', 'SUPABASE_SERVICE_ROLE_KEY', 'SUPABASE_DB_PASSWORD']) {
    assert.throws(() => assertEphemeralEnvironment({ ...env, [key]: 'synthetic' }));
  }
});

test('private fixture credentials must be outside the checkout and artifacts', () => {
  const env = { GITHUB_WORKSPACE: '/tmp/test/repo', CINEMATIC_FIXTURE_FILE: '/tmp/test/private/fixture.json' };
  assert.equal(fixturePath(env), env.CINEMATIC_FIXTURE_FILE);
  for (const path of ['/tmp/test/repo/fixture.json', '/tmp/test/repo/artifacts/fixture.json', 'fixture.json', undefined]) {
    assert.throws(() => fixturePath({ ...env, CINEMATIC_FIXTURE_FILE: path }));
  }
});

test('denial verifier cannot count a server error or leaked private data as a permission pass', () => {
  assert.doesNotThrow(() => assertDenied({ status: 200, data: { ok: false, error: 'not_found', entity: 'restaurant' } }, 'synthetic'));
  assert.doesNotThrow(() => assertDenied({ status: 403, data: { code: '42501' } }, 'synthetic'));
  assert.doesNotThrow(() => assertDenied({ status: 400, data: { statusCode: '404' } }, 'synthetic'));
  for (const value of [
    { status: 500, data: { error: 'not_found' } },
    { status: 400, data: { error: 'invalid_request' } },
    { status: 404, data: { code: 'PGRST202', message: 'missing RPC' } },
    { status: 200, data: { ok: true, document: {} } },
    { status: 200, data: { ok: false, error: 'not_found', entity: 'restaurant', privateKey: 'leak' } },
  ]) assert.throws(() => assertDenied(value, 'synthetic'));
});

test('RPC denials require the authorized API envelope or SQLSTATE42501, not arbitrary404', () => {
  assert.doesNotThrow(() => assertRpcDenied({ status: 403, data: { code: '42501' } }, 'synthetic'));
  assert.doesNotThrow(() => assertRpcDenied({ status: 200, data: { ok: false, error: 'permission_denied', entity: 'restaurant' } }, 'synthetic'));
  for (const value of [
    { status: 404, data: { error: 'not_found' } },
    { status: 403, data: { error: 'gateway_forbidden' } },
    { status: 401, data: { code: 'PGRST301' } },
  ]) assert.throws(() => assertRpcDenied(value, 'synthetic'));
});
