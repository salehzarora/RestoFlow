import test from 'node:test';
import assert from 'node:assert/strict';
import { localStatus } from './ci-runtime.mjs';
const key = role => `test.${Buffer.from(JSON.stringify({ role })).toString('base64url')}.test`;
test('only the local gateway and anon role enter application builds', () => {
  assert.equal(localStatus({ API_URL: 'http://127.0.0.1:54321', ANON_KEY: key('anon') }).url, 'http://127.0.0.1:54321');
  for (const url of ['https://test.supabase.co', 'http://localhost:54321', 'http://127.0.0.1:54321.evil.test', 'http://127.0.0.1:54321/path']) {
    assert.throws(() => localStatus({ API_URL: url, ANON_KEY: key('anon') }));
  }
  for (const role of ['service_role', 'authenticated', undefined]) {
    assert.throws(() => localStatus({ API_URL: 'http://127.0.0.1:54321', ANON_KEY: key(role) }));
  }
  assert.throws(() => localStatus({ API_URL: 'http://127.0.0.1:54321', ANON_KEY: 'malformed' }));
});
