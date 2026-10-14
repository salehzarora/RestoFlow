import './support/ts-resolver.mjs';
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { NOW, REQUEST_ID, SLUG, TOKEN, record, memoryStorage, testCrypto } from './sf-web-orders-fixtures.mjs';
const { createOrderIdentity, OrderIdentityError } = await import('../src/orders/identity.ts');
const { recoveryKey, readRecovery, saveRecovery, clearRecovery, browserRecoveryStorage } = await import('../src/orders/recovery.ts');
const { RECOVERY_MAX_AGE_MS } = await import('../src/orders/contract.ts');

test('identity requires Web Crypto UUIDv4 and exactly 32 CSPRNG bytes', () => {
  let requested = 0;
  const generated = createOrderIdentity(SLUG, NOW, { ...testCrypto(), getRandomValues(bytes) { requested = bytes.byteLength; bytes.fill(1); return bytes; } });
  assert.equal(requested, 32); assert.equal(generated.request_id, REQUEST_ID); assert.equal(generated.status_token, TOKEN);
  assert.equal(generated.status_token.length, 43); assert.equal(Buffer.from(generated.status_token, 'base64url').length, 32);
  assert.equal(generated.expires_at - generated.created_at, RECOVERY_MAX_AGE_MS);
  assert.equal(Object.isFrozen(generated), true);
});
test('real Web Crypto creates distinct valid identities and canonical capabilities', () => {
  const a = createOrderIdentity(SLUG, NOW); const b = createOrderIdentity(SLUG, NOW);
  assert.notEqual(a.request_id, b.request_id); assert.notEqual(a.status_token, b.status_token);
  assert.match(a.request_id, /^[a-f0-9-]{14}4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/);
  assert.equal(Buffer.from(a.status_token, 'base64url').toString('base64url'), a.status_token);
});
test('missing or invalid crypto fails closed with opaque fixed diagnostics', () => {
  for (const crypto of [null, {}, { ...testCrypto(), randomUUID: () => 'not-secure' }, { ...testCrypto(), getRandomValues() { throw new Error('PRIVATE'); } }]) assert.throws(() => createOrderIdentity(SLUG, NOW, crypto), (error) => error instanceof OrderIdentityError && error.message === 'crypto_unavailable');
});
test('recovery persists exactly identity and timestamps, scoped to tenant slug', () => {
  const storage = memoryStorage();
  assert.equal(recoveryKey(SLUG), 'bizbot:web-order:test-kitchen');
  assert.equal(saveRecovery(storage, { ...record(), customer: { name: 'PRIVATE' }, items: [1], notes: 'PRIVATE' }, NOW), true);
  const saved = JSON.parse(storage.getItem(recoveryKey(SLUG)));
  assert.deepEqual(Object.keys(saved), ['slug', 'request_id', 'status_token', 'created_at', 'expires_at']);
  assert.equal(JSON.stringify(saved).includes('PRIVATE'), false);
  assert.deepEqual(readRecovery(storage, SLUG, NOW), { kind: 'record', record: record() });
  assert.deepEqual(readRecovery(storage, 'other-kitchen', NOW), { kind: 'missing' });
});
test('invalid recovery is removed and tenant substitution never authorizes a read', () => {
  for (const value of [{ ...record(), slug: 'other-kitchen' }, { ...record(), status_token: TOKEN.slice(0, -1) + 'B' }, { ...record(), request_id: 'bad' }, { ...record(), customer: 'PRIVATE' }, { ...record(), created_at: NOW + 1 }, { ...record(), expires_at: NOW + RECOVERY_MAX_AGE_MS + 1 }]) {
    const storage = memoryStorage([[recoveryKey(SLUG), JSON.stringify(value)]]);
    assert.deepEqual(readRecovery(storage, SLUG, NOW), { kind: 'invalid' });
    assert.equal(storage.getItem(recoveryKey(SLUG)), null);
  }
});
test('duplicate decoded keys, corrupt JSON and oversized records are cleared', () => {
  const key = recoveryKey(SLUG);
  for (const value of ['{bad', 'x'.repeat(1025), JSON.stringify(record()).replace('"slug":', '"slug":"other","sl\\u0075g":')]) {
    const storage = memoryStorage([[key, value]]);
    assert.equal(readRecovery(storage, SLUG, NOW).kind, 'invalid'); assert.equal(storage.getItem(key), null);
  }
});
test('expiry is enforced at 24 hours exactly and expired records are cleared', () => {
  const storage = memoryStorage([[recoveryKey(SLUG), JSON.stringify(record())]]);
  assert.equal(readRecovery(storage, SLUG, NOW + RECOVERY_MAX_AGE_MS - 1).kind, 'record');
  assert.equal(readRecovery(storage, SLUG, NOW + RECOVERY_MAX_AGE_MS).kind, 'expired');
  assert.equal(storage.getItem(recoveryKey(SLUG)), null);
  assert.equal(saveRecovery(storage, record(), NOW + RECOVERY_MAX_AGE_MS), false);
});
test('blocked, discarded or nonclearable storage fails closed', () => {
  const denied = { getItem() { throw new Error('PRIVATE'); }, setItem() { throw new Error('PRIVATE'); }, removeItem() { throw new Error('PRIVATE'); } };
  assert.equal(readRecovery(denied, SLUG, NOW).kind, 'blocked'); assert.equal(saveRecovery(denied, record(), NOW), false); assert.equal(clearRecovery(denied, SLUG), false);
  assert.equal(readRecovery(null, SLUG, NOW).kind, 'blocked'); assert.equal(browserRecoveryStorage(), null);
  const discards = { getItem: () => null, setItem() {}, removeItem() {} };
  assert.equal(saveRecovery(discards, record(), NOW), false);
  const cannotClear = { getItem: () => '{}', removeItem() {}, setItem() {} };
  assert.equal(readRecovery(cannotClear, SLUG, NOW).kind, 'blocked');
});
