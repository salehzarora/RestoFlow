import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { bootstrapFailureEvidence, bootstrapResponseEvidence, createBootstrapDiagnostics } from './bootstrap-diagnostics.mjs';

test('bootstrap failure exports known numeric/assertion enums and never raw error or identifiers', () => {
  const secret = 'PRIVATE_PASSWORD_URL_SQL_AND_STORAGE_KEY';
  const error = new assert.AssertionError({ actual: 1, expected: 0, message: secret });
  assert.deepEqual(bootstrapFailureEvidence(error), { errorType: 'AssertionError', errorCode: 'ERR_ASSERTION', sqlState: null, actual: 1, expected: 0 });
  const unknown = bootstrapFailureEvidence({ name: secret, code: secret, message: secret, actual: { password: secret }, expected: secret, stack: secret });
  assert.deepEqual(unknown, { errorType: 'unclassified', errorCode: 'unclassified', sqlState: null, actual: null, expected: null });
  assert.equal(JSON.stringify(unknown).includes(secret), false);
  assert.equal(bootstrapFailureEvidence({ code: '23505' }).sqlState, '23505');
  assert.equal(bootstrapFailureEvidence({ code: 'ABCDE' }).sqlState, null);
  assert.equal(bootstrapFailureEvidence({ actual: 'published', expected: true }).actual, 'published');
});

test('readiness evidence uses only match booleans and never accepts or exports body lookalikes', () => {
  const expected = { status: 400, data: { ok: false, status: 'invalid_request', field: 'request_id', reason: 'missing' } };
  assert.ok(Object.values(bootstrapResponseEvidence(expected, true).readiness).every(value => value === true));
  const changes = [['http400', { ...expected, status: 401 }], ['objectBody', { status: 400, data: null }],
    ['exactKeys', { status: 400, data: { ...expected.data, password: 'secret' } }],
    ['okFalse', { status: 400, data: { ...expected.data, ok: true } }],
    ['invalidRequestStatus', { status: 400, data: { ...expected.data, status: 'secret' } }],
    ['requestIdField', { status: 400, data: { ...expected.data, field: 'body', reason: 'json' } }],
    ['missingReason', { status: 400, data: { ...expected.data, reason: 'secret' } }]];
  for (const [key, response] of changes) {
    const evidence = bootstrapResponseEvidence(response, true);
    assert.equal(evidence.readiness.matches, false); assert.equal(evidence.readiness[key], false);
    assert.ok(Object.values(evidence.readiness).every(value => typeof value === 'boolean'));
    assert.equal(JSON.stringify(evidence).includes('secret'), false);
  }
});

test('bootstrap stage receipt retains failure at the exact fixed stage and rejects arbitrary stages', () => {
  const dir = mkdtempSync(join(tmpdir(), 'cinematic-bootstrap-diagnostic-'));
  try {
    const d = createBootstrapDiagnostics(dir), read = () => JSON.parse(readFileSync(join(dir, 'bootstrap-stage.json'), 'utf8'));
    d.advance('seed_catalogue'); d.process({ status: 1, stderr: 'private URL SQLSTATE 23505 private SQL', stdout: 'secret' });
    d.fail(new assert.AssertionError({ actual: 1, expected: 0, message: 'private SQL' }));
    assert.equal(read().stage, 'seed_catalogue'); assert.equal(read().status, 'FAIL');
    assert.deepEqual(read().observation, { exitCode: 1, sqlState: '23505' });
    assert.equal(JSON.stringify(read()).includes('private'), false);
    d.process({ status: 1, stderr: 'psql:<stdin>:1: ERROR: 23503\nprivate statement must not escape' });
    assert.deepEqual(read().observation, { exitCode: 1, sqlState: '23503' });
    assert.equal(JSON.stringify(read()).includes('private'), false);
    assert.throws(() => d.advance('secret-stage'), /Unknown bootstrap diagnostic stage/);
    assert.equal(read().stage, 'seed_catalogue');
    d.advance('a_owner_list'); d.response({ status: 403, data: { ok: false, code: '42501', token: 'secret' } });
    assert.deepEqual(read().observation, { httpStatus: 403, ok: false, sqlState: '42501' });
    d.complete(); assert.equal(read().status, 'PASS'); assert.equal(read().stage, 'complete');
  } finally { rmSync(dir, { recursive: true, force: true }); }
});
