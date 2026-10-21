import './support/ts-resolver.mjs';
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { NOW, SLUG, TOKEN, REQUEST_ID, memoryStorage, testCrypto, record, order, result, response } from './sf-web-orders-fixtures.mjs';
const { createOrderController, WEB_ORDER_ORIGIN, RECOVERY_MAX_AGE_MS } = await import('../src/orders/index.ts');
const { recoveryKey } = await import('../src/orders/recovery.ts');

function setup(fetchImpl, over = {}) {
  const storage = over.storage ?? memoryStorage();
  return { storage, controller: createOrderController({ slug: SLUG, origin: WEB_ORDER_ORIGIN, storage, now: () => NOW, cryptoImpl: testCrypto(), fetchImpl, ...over }) };
}
test('successful submit means pending with server totals, never restaurant acceptance', async () => {
  const phases = [];
  const { storage, controller } = setup(async () => response(result()));
  const unsubscribe = controller.subscribe(() => phases.push(controller.getSnapshot().phase));
  const snapshot = await controller.submit(order()); unsubscribe();
  assert.equal(snapshot.phase, 'status'); assert.equal(snapshot.result.status, 'pending'); assert.equal(snapshot.result.totals.grand_total_minor, 1180);
  assert.equal(snapshot.canRetry, false); assert.equal(snapshot.recovered, false); assert.ok(phases.includes('submitting'));
  const saved = storage.getItem(recoveryKey(SLUG));
  assert.equal(saved.includes('Test Customer'), false); assert.equal(saved.includes('No onion'), false); assert.equal(saved.includes('Pickup'), false);
  assert.equal(JSON.stringify(snapshot).includes(TOKEN), false);
});
test('rapid duplicate submit calls share a single flight and exact original submission', async () => {
  let release;
  let calls = 0;
  const { controller } = setup(async () => { calls++; await new Promise((resolve) => { release = resolve; }); return response(result()); });
  const one = controller.submit(order()); const two = controller.submit(order({ notes: 'changed' }));
  assert.equal(one, two);
  await new Promise((resolve) => setImmediate(resolve));
  assert.equal(calls, 1); release(); await one;
});
test('lost response after commit is reconciled by status and never creates a second canonical submission', async () => {
  const actions = []; let committed = 0;
  const { controller } = setup(async (_url, init) => {
    const body = JSON.parse(init.body); actions.push(body.action);
    if (body.action === 'submit') { committed++; throw new Error('response lost after commit'); }
    return response(result('pending', { replayed: true }));
  });
  const snapshot = await controller.submit(order());
  assert.deepEqual(actions, ['submit', 'status']); assert.equal(committed, 1); assert.equal(snapshot.result.status, 'pending'); assert.equal(snapshot.canRetry, false);
  await controller.retry(); assert.equal(committed, 1);
});
test('explicit retry after not_found rechecks status and uses the identical ID, token and frozen body', async () => {
  const calls = []; let writes = 0;
  const input = order();
  const { controller } = setup(async (_url, init) => {
    calls.push(init.body); const body = JSON.parse(init.body);
    if (body.action === 'status') return response({ ok: false, error: 'not_found' }, 404);
    writes++; return writes === 1 ? response({ ok: false, error: 'submission_outcome_unknown', request_id: REQUEST_ID, uncertain: true }, 503) : response(result());
  });
  const uncertain = await controller.submit(input); assert.equal(uncertain.phase, 'not_found'); assert.equal(uncertain.canRetry, true); assert.equal(writes, 1);
  input.customer.name = 'Changed Customer'; input.items[0].notes = 'Changed note';
  await controller.retry();
  assert.deepEqual(calls.map((body) => JSON.parse(body).action), ['submit', 'status', 'status', 'submit']);
  assert.equal(calls[0], calls[3]); assert.equal(writes, 2);
});
test('explicit retry status that discovers the committed request suppresses the second write', async () => {
  let writes = 0; let reads = 0;
  const { controller } = setup(async (_url, init) => {
    if (JSON.parse(init.body).action === 'submit') { writes++; throw new Error('lost'); }
    reads++; return reads === 1 ? response({ ok: false, error: 'not_found' }, 404) : response(result('accepted'));
  });
  assert.equal((await controller.submit(order())).canRetry, true);
  assert.equal((await controller.retry()).result.status, 'accepted'); assert.equal(writes, 1);
});
test('unavailable reconciliation remains unknown and prohibits blind write retries', async () => {
  const actions = [];
  const { controller } = setup(async (_url, init) => { actions.push(JSON.parse(init.body).action); throw new Error('offline'); });
  const snapshot = await controller.submit(order()); assert.equal(snapshot.phase, 'unknown'); assert.equal(snapshot.canRetry, false); assert.equal(snapshot.result, null);
  await controller.retry(); assert.deepEqual(actions, ['submit', 'status']);
  await controller.refresh(); assert.deepEqual(actions, ['submit', 'status', 'status']);
});
test('reload recovers status only and never blindly resubmits an order', async () => {
  const storage = memoryStorage([[recoveryKey(SLUG), JSON.stringify(record())]]); const actions = [];
  const { controller } = setup(async (_url, init) => { actions.push(JSON.parse(init.body)); return response({ ok: false, error: 'not_found' }, 404); }, { storage });
  const snapshot = await controller.recover(); assert.equal(snapshot.recovered, true); assert.equal(snapshot.canRetry, false); assert.equal(snapshot.phase, 'not_found');
  await controller.retry(); await controller.submit(order());
  assert.deepEqual(actions.map((body) => body.action), ['status', 'status']); assert.ok(actions.every((body) => !Object.hasOwn(body, 'order')));
});
test('request acceptance, rejection and expiry remain recoverable past pending deadline until capability TTL', async () => {
  for (const status of ['accepted', 'rejected', 'expired']) {
    const storage = memoryStorage(); let current = NOW;
    const fetchImpl = async () => response(result(status, { expires_at: new Date(NOW + 900_000).toISOString() }));
    const first = setup(fetchImpl, { storage, now: () => current }).controller;
    await first.submit(order());
    assert.equal(JSON.parse(storage.getItem(recoveryKey(SLUG))).expires_at, NOW + RECOVERY_MAX_AGE_MS);
    current = NOW + 3_600_000;
    const reloaded = setup(fetchImpl, { storage, now: () => current }).controller;
    const recovered = await reloaded.recover();
    assert.equal(recovered.result.status, status); assert.equal(recovered.recovered, true); assert.equal(recovered.canRetry, false);
  }
});
test('status transitions truthfully expose pending then accepted/rejected/expired', async () => {
  for (const status of ['accepted', 'rejected', 'expired']) {
    let first = true;
    const { controller } = setup(async () => { const current = first ? 'pending' : status; first = false; return response(result(current)); });
    assert.equal((await controller.submit(order())).result.status, 'pending');
    assert.equal((await controller.refresh()).result.status, status);
  }
});
test('public rejection reason survives capability-only recovery without persistence or a repeated submission', async () => {
  const reason = 'Synthetic public reason الصنف غير متوفر';
  const storage = memoryStorage(); const actions = [];
  const fetchImpl = async (_url, init) => {
    const body = JSON.parse(init.body); actions.push(body);
    return response(body.action === 'submit' ? result() : result('rejected', { replayed: true, customer_rejection_reason: reason }));
  };
  const first = setup(fetchImpl, { storage }).controller;
  assert.equal((await first.submit(order())).result.status, 'pending');
  const rejected = await first.refresh();
  assert.equal(rejected.result.customer_rejection_reason, reason); assert.equal(rejected.canRetry, false);
  await first.retry();
  const reloaded = setup(fetchImpl, { storage }).controller;
  assert.equal((await reloaded.recover()).result.customer_rejection_reason, reason);
  assert.equal(actions.filter((body) => body.action === 'submit').length, 1);
  assert.ok(actions.filter((body) => body.action === 'status').every((body) => Object.keys(body).sort().join(',') === 'action,request_id,slug,status_token'));
  assert.equal([...storage.map.values()].some((value) => value.includes(reason)), false);
});
test('confirmed terminal status never regresses and known requests never become write retries', async () => {
  let calls = 0;
  const { controller } = setup(async () => { calls++; return calls === 1 ? response(result('accepted')) : calls === 2 ? response(result('pending')) : response({ ok: false, error: 'not_found' }, 404); });
  await controller.submit(order());
  const regression = await controller.refresh(); assert.equal(regression.result.status, 'accepted'); assert.equal(regression.phase, 'unavailable');
  assert.equal((await controller.refresh()).canRetry, false);
});
test('storage blocked or invalid/expired recovery prevents any submit or status I/O', async () => {
  let calls = 0;
  const denied = { getItem() { throw new Error('blocked'); }, setItem() { throw new Error('blocked'); }, removeItem() { throw new Error('blocked'); } };
  const bad = memoryStorage([[recoveryKey(SLUG), '{}']]);
  const expired = memoryStorage([[recoveryKey(SLUG), JSON.stringify(record({ created_at: NOW - RECOVERY_MAX_AGE_MS, expires_at: NOW }))]]);
  for (const [storage, error] of [[denied, 'storage_unavailable'], [bad, 'recovery_invalid'], [expired, 'recovery_expired']]) {
    const { controller } = setup(async () => { calls++; return response(result()); }, { storage });
    assert.equal((await controller.submit(order())).error, error);
  }
  assert.equal(calls, 0);
});
test('failure to persist verified recovery stops before first write', async () => {
  let calls = 0;
  const storage = { getItem: () => null, setItem() {}, removeItem() {} };
  const { controller } = setup(async () => { calls++; return response(result()); }, { storage });
  assert.equal((await controller.submit(order())).error, 'storage_unavailable'); assert.equal(calls, 0);
});
test('blocked or substituted recovery prevents an explicit retry write', async () => {
  let writes = 0; let blocked = false;
  const storage = memoryStorage(); const read = storage.getItem;
  storage.getItem = (key) => { if (blocked) throw new Error('blocked'); return read(key); };
  const { controller } = setup(async (_url, init) => { if (JSON.parse(init.body).action === 'submit') { writes++; throw new Error('lost'); } return response({ ok: false, error: 'not_found' }, 404); }, { storage });
  await controller.submit(order()); blocked = true;
  assert.equal((await controller.retry()).error, 'storage_unavailable'); assert.equal(writes, 1);
});
test('identity expiry drops the frozen payload and cannot repeat the write', async () => {
  let current = NOW; let writes = 0;
  const { controller, storage } = setup(async (_url, init) => { if (JSON.parse(init.body).action === 'submit') { writes++; throw new Error('lost'); } return response({ ok: false, error: 'not_found' }, 404); }, { now: () => current });
  await controller.submit(order()); current += RECOVERY_MAX_AGE_MS;
  assert.equal((await controller.retry()).error, 'recovery_expired'); assert.equal(writes, 1); assert.equal(storage.getItem(recoveryKey(SLUG)), null);
});
test('definitive admission failure leaves no recovery record and permits explicit corrected submission', async () => {
  let calls = 0;
  const { controller, storage } = setup(async () => { calls++; return calls === 1 ? response({ ok: false, error: 'item_unavailable' }, 422) : response(result()); });
  assert.equal((await controller.submit(order())).error, 'item_unavailable'); assert.equal(storage.getItem(recoveryKey(SLUG)), null);
  assert.equal((await controller.submit(order())).result.status, 'pending'); assert.equal(calls, 2);
});
test('a different tenant never reads or writes using another tenant capability', async () => {
  const storage = memoryStorage([[recoveryKey(SLUG), JSON.stringify(record())]]); let calls = 0;
  const { controller } = setup(async () => { calls++; return response(result()); }, { slug: 'other-kitchen', storage });
  assert.equal((await controller.recover()).phase, 'idle'); assert.equal(calls, 0); assert.notEqual(storage.getItem(recoveryKey(SLUG)), null);
});
test('status remains available while submission gate refuses writes', async () => {
  const { controller, storage } = setup(async (_url, init) => JSON.parse(init.body).action === 'status' ? response(result('accepted')) : response({ ok: false, error: 'ordering_unavailable' }, 503));
  assert.equal((await controller.submit(order())).error, 'ordering_unavailable');
  storage.setItem(recoveryKey(SLUG), JSON.stringify(record()));
  assert.equal((await controller.recover()).result.status, 'accepted');
});
test('explicit order again clears only this tenant after a known terminal result and generates a fresh identity on submit', async () => {
  for (const status of ['accepted', 'rejected', 'expired']) {
    const storage = memoryStorage([[recoveryKey('other-kitchen'), 'other tenant recovery']]);
    let generated = 0; const ids = [];
    const cryptoImpl = { ...testCrypto(), randomUUID: () => generated++ === 0 ? REQUEST_ID : '44444444-4444-4444-8444-444444444444' };
    const { controller } = setup(async (_url, init) => {
      const body = JSON.parse(init.body); ids.push(body.request_id);
      return response(result(ids.length === 1 ? status : 'pending', { request_id: body.request_id }));
    }, { storage, cryptoImpl });
    await controller.submit(order());
    assert.equal(controller.startNewOrder().phase, 'idle');
    assert.equal(storage.getItem(recoveryKey(SLUG)), null);
    assert.equal(storage.getItem(recoveryKey('other-kitchen')), 'other tenant recovery');
    assert.equal(generated, 1, 'reset itself never generates or submits a new identity');
    assert.equal((await controller.submit(order())).result.status, 'pending');
    assert.notEqual(ids[0], ids[1]);
  }
});
test('order again cannot discard pending, unknown or not-found requests', async () => {
  for (const mode of ['pending', 'unknown', 'not_found']) {
    const { controller, storage } = setup(async (_url, init) => {
      const action = JSON.parse(init.body).action;
      if (mode === 'pending') return response(result());
      if (mode === 'unknown' || action === 'submit') throw new Error('lost');
      return response({ ok: false, error: 'not_found' }, 404);
    });
    const before = await controller.submit(order()); const saved = storage.getItem(recoveryKey(SLUG));
    assert.equal(controller.startNewOrder(), before);
    assert.equal(storage.getItem(recoveryKey(SLUG)), saved);
  }
});
test('order again denies an active status flight and preserves terminal recovery when storage clear is blocked', async () => {
  const storage = memoryStorage(); let release; let blockClear = false; let calls = 0;
  const remove = storage.removeItem;
  storage.removeItem = (key) => { if (blockClear) throw new Error('blocked'); remove(key); };
  const { controller } = setup(async () => {
    calls++;
    if (calls > 1) await new Promise((resolve) => { release = resolve; });
    return response(result('accepted'));
  }, { storage });
  await controller.submit(order());
  const flight = controller.refresh(); await new Promise((resolve) => setImmediate(resolve));
  const busy = controller.getSnapshot(); const saved = storage.getItem(recoveryKey(SLUG));
  assert.equal(controller.startNewOrder(), busy); assert.equal(storage.getItem(recoveryKey(SLUG)), saved);
  release(); await flight; blockClear = true;
  const denied = controller.startNewOrder();
  assert.equal(denied.error, 'storage_unavailable'); assert.equal(denied.result.status, 'accepted');
  assert.equal(storage.getItem(recoveryKey(SLUG)), saved);
});
