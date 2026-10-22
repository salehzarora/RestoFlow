import './support/ts-resolver.mjs';
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { registerHooks, stripTypeScriptTypes } from 'node:module';
import { identity, order, result, response, NOW, SLUG, memoryStorage, testCrypto } from './sf-web-orders-fixtures.mjs';
const { createOrderTransport, decodeOrderResponse, createOrderController, WEB_ORDER_ORIGIN } = await import('../src/orders/index.ts');
const { decodeAcceptanceEta } = await import('../src/orders/acceptanceEta.ts');
const { acceptanceEtaCopy } = await import('../src/i18n/acceptanceEta.ts');
const { orderMessages } = await import('../src/i18n/orders.ts');

const HEADER = 'X-BIZBOT-Order-Response-Version';
const eta = (over = {}) => ({ preparation_minutes: 15, accepted_at: '2026-10-22T20:55:00.123456Z', ready_at: '2026-10-22T21:10:00.123456Z', timezone: 'Asia/Jerusalem', ...over });
const withEta = (over = {}) => result('accepted', { acceptance_eta: eta(), ...over });

test('strict optional ETA is accepted only by negotiated status2; legacy bodies stay exact', () => {
  const known = decodeOrderResponse(withEta(), 200, identity(), 'status', '2');
  assert.deepEqual(known.result.acceptance_eta, eta());
  assert.ok(Object.isFrozen(known.result.acceptance_eta));
  assert.throws(() => decodeOrderResponse(withEta(), 200, identity(), 'status'));
  assert.throws(() => decodeOrderResponse(withEta(), 200, identity(), 'submit', '2'));
  for (const state of ['pending', 'rejected', 'expired']) assert.throws(() => decodeOrderResponse(result(state, { acceptance_eta: eta() }), 200, identity(), 'status', '2'));
  assert.equal(Object.hasOwn(decodeOrderResponse(result('accepted'), 200, identity(), 'status', '2').result, 'acceptance_eta'), false);
});

test('tuple rejects missing/unknown fields, types, invalid calendars/zones and inexact arithmetic', () => {
  for (const value of [null, [], {}, { ...eta(), internal_request: 'private' }, ...Object.keys(eta()).map(key => Object.fromEntries(Object.entries(eta()).filter(([name]) => name !== key))),
    ...[0, 241, -1, 1.5, '15', true, null].map(preparation_minutes => eta({ preparation_minutes })),
    ...['UTC+3', 'GMT', 'localtime', 'Factory', 'right/UTC', 'posix/Asia/Jerusalem', 'Not/AZone', ' Asia/Jerusalem', 'Asia/Jerusalem\n'].map(timezone => eta({ timezone })),
    eta({ accepted_at: '2026-02-30T20:55:00.123456Z' }), eta({ accepted_at: '2026-10-22T20:55:00.123456+03:00' }),
    eta({ ready_at: '2026-10-22T21:10:00.123455Z' }), eta({ ready_at: '2026-10-22T21:10:00.1234567Z' }),
  ]) assert.throws(() => decodeAcceptanceEta(value), JSON.stringify(value));
  assert.deepEqual(decodeAcceptanceEta(eta({ accepted_at: '2026-10-22T20:55:00.1+00:00', ready_at: '2026-10-22T21:10:00.1Z' })), eta({ accepted_at: '2026-10-22T20:55:00.100000Z', ready_at: '2026-10-22T21:10:00.100000Z' }));
  for (const timezone of ['UTC', 'Asia/Jerusalem', 'Europe/London', 'America/New_York', 'Etc/GMT+2']) assert.equal(decodeAcceptanceEta(eta({ timezone })).timezone, timezone);
});

test('status requires exact acknowledgment on success and fixed errors, without a fallback call', async () => {
  for (const acknowledgment of [null, '', '1', '02', '2, 2', ' 2,1']) {
    let calls = 0;
    const api = createOrderTransport({ origin: WEB_ORDER_ORIGIN, fetchImpl: async () => {
      calls++;
      const reply = response(withEta());
      if (acknowledgment === null) reply.headers.delete(HEADER); else reply.headers.set(HEADER, acknowledgment);
      return reply;
    } });
    assert.deepEqual(await api.status(identity()), { kind: 'unavailable', error: 'status_unavailable' });
    assert.equal(calls, 1);
  }
  for (const state of ['pending', 'accepted', 'rejected', 'expired']) {
    const api = createOrderTransport({ origin: WEB_ORDER_ORIGIN, fetchImpl: async () => response(result(state)) });
    assert.equal((await api.status(identity())).result.status, state);
  }
  const api = createOrderTransport({ origin: WEB_ORDER_ORIGIN, fetchImpl: async () => response({ ok: false, error: 'not_found' }, 404) });
  assert.deepEqual(await api.status(identity()), { kind: 'failure', error: 'not_found' });
});

test('accepted submit replay obtains at most one status read and preserves confirmed acceptance if it fails', async () => {
  for (const mode of ['eta', 'legacy', 'failure', 'wrong-ack']) {
    const calls = [], storage = memoryStorage();
    const controller = createOrderController({ slug: SLUG, origin: WEB_ORDER_ORIGIN, storage, now: () => NOW, cryptoImpl: testCrypto(), fetchImpl: async (_url, init) => {
      const body = JSON.parse(init.body); calls.push({ body, headers: init.headers });
      if (body.action === 'submit') return response(result('accepted', { replayed: true }));
      if (mode === 'failure') throw new Error('synthetic read failure');
      return response(mode === 'eta' ? withEta() : result('accepted'), 200, mode === 'wrong-ack' ? { [HEADER]: '1' } : {});
    } });
    const snapshot = await controller.submit(order());
    assert.equal(snapshot.result.status, 'accepted');
    assert.equal(snapshot.canRetry, false);
    assert.deepEqual(calls.map(call => call.body.action), ['submit', 'status']);
    assert.equal(Object.hasOwn(calls[0].headers, HEADER), false);
    assert.equal(calls[1].headers[HEADER], '2');
    assert.deepEqual(calls[0].body, { action: 'submit', ...identity(), order: order() });
    assert.equal(Object.hasOwn(snapshot.result, 'acceptance_eta'), mode === 'eta');
    assert.equal(snapshot.phase, ['failure', 'wrong-ack'].includes(mode) ? 'unavailable' : 'status');
    for (const stored of storage.map.values()) for (const forbidden of ['acceptance_eta', 'preparation_minutes', 'accepted_at', 'Test Customer', 'No onion']) assert.equal(stored.includes(forbidden), false);
    await controller.retry();
    assert.equal(calls.filter(call => call.body.action === 'submit').length, 1);
  }
});

test('immutable confirmed ETA survives failed, missing and changed subsequent reads', async () => {
  for (const next of ['failure', 'absent', 'changed']) {
    let reads = 0;
    const controller = createOrderController({ slug: SLUG, origin: WEB_ORDER_ORIGIN, storage: memoryStorage(), now: () => NOW, cryptoImpl: testCrypto(), fetchImpl: async (_url, init) => {
      if (JSON.parse(init.body).action === 'submit') return response(result());
      if (++reads === 1) return response(withEta());
      if (next === 'failure') throw new Error('synthetic');
      return response(next === 'absent' ? result('accepted') : withEta({ acceptance_eta: eta({ timezone: 'Europe/London' }) }));
    } });
    await controller.submit(order()); await controller.refresh();
    const snapshot = await controller.refresh();
    assert.equal(snapshot.result.status, 'accepted'); assert.equal(snapshot.phase, 'unavailable');
    assert.deepEqual(snapshot.result.acceptance_eta, eta());
    assert.equal(snapshot.canRetry, false);
  }
});

test('AR/HE/EN show approximate duration and absolute stored-zone date across midnight/DST, no countdown', () => {
  for (const locale of ['ar', 'he', 'en']) for (const estimate of [eta(), eta({ accepted_at: '2026-11-01T05:55:00.000000Z', ready_at: '2026-11-01T06:10:00.000000Z', timezone: 'America/New_York' })]) {
    const copy = acceptanceEtaCopy(estimate, locale, orderMessages(locale));
    assert.ok(copy.duration.length > 0 && copy.ready.length > 0);
    const expected = new Intl.DateTimeFormat(locale, { timeZone: estimate.timezone, dateStyle: 'medium', timeStyle: 'short' }).format(new Date(estimate.ready_at));
    assert.ok(copy.ready.includes(expected)); assert.equal(copy.timezone, estimate.timezone);
    assert.deepEqual(acceptanceEtaCopy(estimate, locale, orderMessages(locale)), copy);
    assert.ok(!copy.duration.includes('{minutes}') && !copy.ready.includes('{time}'));
  }
  const ui = readFileSync(new URL('../src/ui/storefront/request/LiveRequestRuntime.tsx', import.meta.url), 'utf8');
  assert.ok(ui.includes("status === 'accepted' && result?.acceptance_eta"));
  assert.ok(ui.includes('data-sf-acceptance-eta'));
  assert.ok(!ui.includes('dangerouslySetInnerHTML'));
});

// Preserve and actually instantiate the old transport/strict decoder. It stays
// alive across the synthetic backend update, without reload/new request/body.
const original = readFileSync(new URL('./support/legacy-transport-v1.ts.txt', import.meta.url), 'utf8');
assert.equal(createHash('sha256').update(original).digest('hex'), '63c078473211d3deb9d1d522533205343acdd69cb0ee606d3faf37ad5d87f288');
const oldUrl = new URL('../src/orders/pre-eta-transport.ts', import.meta.url).href;
registerHooks({
  resolve(specifier, context, next) { return specifier === oldUrl ? { url: oldUrl, shortCircuit: true } : next(specifier, context); },
  load(url, context, next) { return url === oldUrl ? { format: 'module', source: stripTypeScriptTypes(original), shortCircuit: true } : next(url, context); },
});
const { createOrderTransport: oldTransport, decodeOrderResponse: oldDecode } = await import(oldUrl);

test('old-open transport and strict decoder remain compatible across ETA-capable acceptance; mixed matrix', async () => {
  let accepted = false;
  const calls = [];
  // Projection fixtures here are later cross-checked against the real new Edge
  // handler. The old retained transport itself is unmodified pinned source.
  const fetchImpl = async (_url, init) => {
    const body = JSON.parse(init.body); calls.push({ body, header: init.headers[HEADER] });
    return response(!accepted ? result() : init.headers[HEADER] === '2' ? withEta() : result('accepted'));
  };
  const oldTab = oldTransport({ origin: WEB_ORDER_ORIGIN, fetchImpl });
  assert.equal((await oldTab.status(identity())).result.status, 'pending');
  accepted = true;
  const legacy = await oldTab.status(identity());
  assert.equal(legacy.result.status, 'accepted'); assert.equal(Object.hasOwn(legacy.result, 'acceptance_eta'), false);
  assert.equal(calls.length, 2); assert.ok(calls.every(call => call.body.action === 'status' && call.header === undefined));
  assert.throws(() => oldDecode(withEta(), 200, identity(), 'status'), 'old strict decoder must actually reject the new field');
  const newTab = createOrderTransport({ origin: WEB_ORDER_ORIGIN, fetchImpl });
  assert.deepEqual((await newTab.status(identity())).result.acceptance_eta, eta());
  const oldPos = createOrderTransport({ origin: WEB_ORDER_ORIGIN, fetchImpl: async () => response(result('accepted')) });
  assert.equal(Object.hasOwn((await oldPos.status(identity())).result, 'acceptance_eta'), false);
});

test('retained old tab and new consumer cross the actual new customer/decision handlers in both POS modes', async () => {
  const { createHandler: customerHandler } = await import('../../supabase/functions/web-order-submit/handler.mjs');
  const { createHandler: decisionHandler } = await import('../../supabase/functions/pos-web-order-decision/handler.mjs');
  const { webcrypto } = await import('node:crypto');
  for (const posEta of [false, true]) {
    let state = 'pending', estimate;
    const browserCalls = [], rpcCalls = [];
    // Old tab begins before the backend update and retains this same transport.
    let activeBackend = async () => Response.json(result());
    const browserFetch = async (url, init) => {
      assert.equal(url, `${WEB_ORDER_ORIGIN}/functions/v1/web-order-submit`);
      browserCalls.push(JSON.parse(init.body));
      return activeBackend(new Request(url, init));
    };
    const oldTab = oldTransport({ origin: WEB_ORDER_ORIGIN, fetchImpl: browserFetch });
    assert.equal((await oldTab.status(identity())).result.status, 'pending');
    // A new consumer cannot silently fall back against the unsupported backend.
    const newTab = createOrderTransport({ origin: WEB_ORDER_ORIGIN, fetchImpl: browserFetch });
    assert.equal((await newTab.status(identity())).kind, 'unavailable');
    activeBackend = customerHandler({ getEnv: key => ({ SUPABASE_URL: 'https://synthetic-project.supabase.co', SUPABASE_SERVICE_ROLE_KEY: 'synthetic-service' })[key], cryptoImpl: webcrypto,
      fetchImpl: async (url, init) => {
        const name = url.split('/').at(-1); rpcCalls.push(name);
        assert.ok(['get_web_order_request_status', 'get_web_order_request_status_v2'].includes(name));
        const args = JSON.parse(init.body);
        assert.equal(args.p_client_request_id, identity().request_id);
        assert.equal(args.p_slug, identity().slug);
        assert.equal(args.p_status_token_hash, createHash('sha256').update(identity().status_token).digest('hex'));
        return Response.json(result(state, name.endsWith('_v2') && estimate ? { acceptance_eta: estimate } : {}));
      } });
    const decisionId = '36600000-0000-4000-8000-000000000004';
    const internalRequestId = '36600000-0000-4000-8000-000000000003';
    let decisionWrites = 0;
    const decide = decisionHandler({ getEnv: key => ({ SUPABASE_URL: 'https://synthetic-project.supabase.co', SUPABASE_ANON_KEY: 'synthetic-public' })[key],
      fetchImpl: async (url, init) => {
        assert.equal(url.split('/').at(-1), posEta ? 'pos_accept_web_order_with_eta' : 'pos_accept_web_order');
        assert.equal(init.headers.Authorization, 'Bearer synthetic.caller.signature');
        const args = JSON.parse(init.body); assert.equal(args.p_request_id, internalRequestId);
        assert.equal(args.p_decision_id, decisionId);
        assert.equal(Object.hasOwn(args, 'p_preparation_minutes'), posEta);
        if (posEta) assert.equal(args.p_preparation_minutes, 15);
        decisionWrites++; state = 'accepted'; estimate = posEta ? eta() : undefined;
        return Response.json({ ok: true, request_id: internalRequestId, status: 'accepted', canonical_order_id: '36600000-0000-4000-8000-000000000005', decision_id: decisionId, replayed: false });
      } });
    const accepted = await decide(new Request('https://edge.test/functions/v1/pos-web-order-decision', { method: 'POST',
      headers: { 'content-type': 'application/json', authorization: 'Bearer synthetic.caller.signature' },
      body: JSON.stringify({ action: 'accept', pin_session_id: '36600000-0000-4000-8000-000000000001', device_id: '36600000-0000-4000-8000-000000000002', device_session_token: 'synthetic-device', request_id: internalRequestId, decision_id: decisionId, ...(posEta ? { preparation_minutes: 15 } : {}) }) }));
    assert.equal(accepted.status, 200); assert.equal((await accepted.json()).status, 'accepted');
    const oldView = await oldTab.status(identity()), newView = await newTab.status(identity());
    assert.equal(oldView.result.status, 'accepted'); assert.equal(Object.hasOwn(oldView.result, 'acceptance_eta'), false);
    assert.equal(newView.result.status, 'accepted'); assert.equal(Object.hasOwn(newView.result, 'acceptance_eta'), posEta);
    if (posEta) assert.deepEqual(newView.result.acceptance_eta, eta());
    assert.equal(decisionWrites, 1); assert.deepEqual(rpcCalls, ['get_web_order_request_status', 'get_web_order_request_status_v2']);
    assert.ok(browserCalls.every(call => call.action === 'status'));
    assert.ok(browserCalls.every(call => call.request_id === identity().request_id && call.status_token === identity().status_token));
  }
});
