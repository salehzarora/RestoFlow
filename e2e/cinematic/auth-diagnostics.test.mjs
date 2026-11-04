import test from 'node:test';
import assert from 'node:assert/strict';
import { isPasswordGrantRequest, authRequestEvidence, authResponseEvidence } from './auth-diagnostics.mjs';

const api = 'http://127.0.0.1:54321';
const endpoint = `${api}/auth/v1/token?grant_type=password`;
const fixture = { email: 'synthetic-private-owner@example.test', password: 'SYNTHETIC_PRIVATE_PASSWORD_123' };
const token = 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJwcml2YXRlIn0.signature';

test('login observer matches only the intended local password grant, not refresh or other auth responses', () => {
  assert.equal(isPasswordGrantRequest(endpoint, 'POST', api), true);
  for (const url of [endpoint.replace('password', 'refresh_token'), `${api}/auth/v1/token`,
    `${endpoint}&grant_type=refresh_token`, `${api}/auth/v1/user?grant_type=password`,
    endpoint.replace('127.0.0.1', 'external.test'), `http://private:secret@127.0.0.1:54321/auth/v1/token?grant_type=password`, 'invalid-url']) {
    assert.equal(isPasswordGrantRequest(url, 'POST', api), false);
  }
  assert.equal(isPasswordGrantRequest(endpoint, 'GET', api), false);
});

test('submitted credentials reduce to equality booleans without retaining fixture or payload', () => {
  const input = JSON.stringify({ ...fixture, access_token: token, url: 'https://private.test/secret' });
  const evidence = authRequestEvidence(endpoint, input, fixture);
  assert.deepEqual(evidence, { grantType: 'password', submittedEmailMatchesFixture: true, submittedPasswordMatchesFixture: true });
  assert.deepEqual(authRequestEvidence(endpoint, JSON.stringify({ email: fixture.email, password: 'wrong' }), fixture),
    { grantType: 'password', submittedEmailMatchesFixture: true, submittedPasswordMatchesFixture: false });
  for (const secret of [fixture.email, fixture.password, token, 'https://private.test/secret']) assert.equal(JSON.stringify(evidence).includes(secret), false);
  for (const body of [null, '{bad-json', 'null', '[]', '{}', JSON.stringify({ email: {}, password: [] })]) {
    const value = authRequestEvidence(endpoint, body, fixture);
    assert.equal(value.submittedEmailMatchesFixture, false);
    assert.equal(value.submittedPasswordMatchesFixture, false);
  }
  assert.equal(authRequestEvidence(endpoint, '{}', {}).submittedEmailMatchesFixture, false);
});

test('Auth response sanitizer preserves known status and code but excludes synthetic secrets and messages', () => {
  const result = authResponseEvidence({ status: 400, contentType: `application/json; private=${token}`,
    data: { code: 400, error_code: 'invalid_credentials', error: 'invalid_grant',
      msg: fixture.password, message: fixture.email, access_token: token, path: '/private/object' },
    headers: { authorization: token }, url: 'https://private.test/path' }, 52.4);
  assert.deepEqual(result, { httpStatus: 400, contentType: 'application/json', errorCode: 'invalid_credentials', oauthError: 'invalid_grant', durationMs: 52 });
  for (const secret of [fixture.email, fixture.password, token, '/private/object', 'https://private.test/path']) assert.equal(JSON.stringify(result).includes(secret), false);
});

test('unknown and malformed Auth data produces only fixed enums and bounded numbers', () => {
  const value = authResponseEvidence({ status: fixture.password, contentType: fixture.email,
    data: { code: token, error: fixture.password } }, Infinity);
  assert.deepEqual(value, { httpStatus: null, contentType: 'unclassified', errorCode: 'unclassified', oauthError: 'unclassified', durationMs: null });
  for (const status of [0, 99, 600, 401.5]) assert.equal(authResponseEvidence({ status }, -1).httpStatus, null);
  for (const duration of [-1, NaN, 120_001]) assert.equal(authResponseEvidence({}, duration).durationMs, null);
  assert.equal(authRequestEvidence(`${api}/auth/v1/token?grant_type=${token}`, '{}', fixture).grantType, 'unclassified');
  assert.equal(authRequestEvidence(`${api}/auth/v1/token`, '{}', fixture).grantType, 'missing');
});

test('successful session body is never retained in PASS diagnostics', () => {
  const evidence = authResponseEvidence({ status: 200, contentType: 'application/json',
    data: { access_token: token, refresh_token: fixture.password, user: { email: fixture.email } } }, 20);
  assert.deepEqual(evidence, { httpStatus: 200, contentType: 'application/json', errorCode: 'missing', oauthError: 'missing', durationMs: 20 });
  for (const secret of [token, fixture.email, fixture.password]) assert.equal(JSON.stringify(evidence).includes(secret), false);
});
